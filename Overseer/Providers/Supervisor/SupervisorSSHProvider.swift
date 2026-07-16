import Foundation

final class SupervisorSSHProvider: ServiceManagerProvider, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let username: String
    private let authenticationMethod: AuthenticationMethod
    private let sshKeyPath: String?
    private let password: String?
    private let supervisorctlPath: String
    private let timeout: TimeInterval

    init(
        host: String,
        port: Int,
        username: String,
        authenticationMethod: AuthenticationMethod,
        sshKeyPath: String?,
        password: String?,
        supervisorctlPath: String,
        timeout: TimeInterval
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMethod = authenticationMethod
        self.sshKeyPath = sshKeyPath
        self.password = password
        self.supervisorctlPath = supervisorctlPath
        self.timeout = timeout
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let output = try await executeRemotely("status")
        return Self.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        _ = try await executeRemotely("start \(Self.shellEscape(name))")
    }

    nonisolated func stopProcess(_ name: String) async throws {
        _ = try await executeRemotely("stop \(Self.shellEscape(name))")
    }

    nonisolated func restartProcess(_ name: String) async throws {
        _ = try await executeRemotely("restart \(Self.shellEscape(name))")
    }

    // MARK: - SSH Execution

    private nonisolated func executeRemotely(_ command: String) async throws -> String {
        let remoteCommand = "\(supervisorctlPath) \(command)"
        var sshArgs = buildSSHArguments()
        sshArgs.append(remoteCommand)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshArgs

        var askpassPath: String?
        defer {
            if let path = askpassPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        if authenticationMethod == .password, let password = password {
            let tempPath = NSTemporaryDirectory() + "overseer_askpass_\(UUID().uuidString).sh"
            let escapedPassword = password
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "'\\''")
            let script = "#!/bin/sh\necho '\(escapedPassword)'\n"
            FileManager.default.createFile(atPath: tempPath, contents: script.data(using: .utf8), attributes: [.posixPermissions: 0o700])
            askpassPath = tempPath

            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = tempPath
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = "none"
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            final class ResumeFlag: @unchecked Sendable { var value = false }
            let resumed = ResumeFlag()
            let lock = NSLock()

            let resumeOnce: @Sendable (Result<String, Error>) -> Void = { result in
                lock.lock()
                guard !resumed.value else { lock.unlock(); return }
                resumed.value = true
                lock.unlock()
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let _ = String(data: stderrData, encoding: .utf8) ?? ""

                resumeOnce(.success(stdout))
            }

            do {
                try process.run()
            } catch {
                resumeOnce(.failure(error))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + self.timeout) { [weak process] in
                process?.terminate()
                resumeOnce(.failure(ConnectionError.timeout))
            }
        }
    }

    private nonisolated func buildSSHArguments() -> [String] {
        var args = [
            "-p", "\(port)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=\(Int(timeout))",
            "-o", "BatchMode=yes"
        ]

        if authenticationMethod == .sshKey, let keyPath = sshKeyPath {
            args.append(contentsOf: ["-i", keyPath])
        }

        if authenticationMethod == .password {
            args.append(contentsOf: ["-o", "BatchMode=no"])
        }

        args.append("\(username)@\(host)")
        return args
    }

    // MARK: - Parsing

    nonisolated static func parseStatusOutput(_ output: String) -> [SupervisorProcess] {
        output.split(separator: "\n").compactMap { line in
            parseProcessLine(String(line))
        }
    }

    private nonisolated static func parseProcessLine(_ line: String) -> SupervisorProcess? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard let nameEnd = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let fullName = String(trimmed[trimmed.startIndex..<nameEnd])

        let rest = trimmed[nameEnd...].trimmingCharacters(in: .whitespaces)
        guard let statusEnd = rest.firstIndex(where: { $0.isWhitespace }) else {
            let status = mapStatus(String(rest))
            return splitName(fullName, status: status, description: String(rest))
        }

        let statusStr = String(rest[rest.startIndex..<statusEnd])
        let description = String(rest[statusEnd...]).trimmingCharacters(in: .whitespaces)
        let status = mapStatus(statusStr)

        return splitName(fullName, status: status, description: description)
    }

    private nonisolated static func splitName(_ fullName: String, status: ServiceStatus, description: String) -> SupervisorProcess {
        let parts = fullName.split(separator: ":", maxSplits: 1)
        if parts.count == 2 {
            return SupervisorProcess(
                name: String(parts[1]),
                group: String(parts[0]),
                status: status,
                description: description,
                pid: extractPid(from: description),
                uptime: nil,
                exitStatus: nil
            )
        }
        return SupervisorProcess(
            name: fullName,
            group: fullName,
            status: status,
            description: description,
            pid: extractPid(from: description),
            uptime: nil,
            exitStatus: nil
        )
    }

    private nonisolated static func mapStatus(_ raw: String) -> ServiceStatus {
        switch raw.uppercased() {
        case "RUNNING": .running
        case "STOPPED": .stopped
        case "STARTING": .starting
        case "BACKOFF": .backingoff
        case "STOPPING": .stopping
        case "EXITED": .exited
        case "FATAL": .fatal
        default: .unknown
        }
    }

    private nonisolated static func extractPid(from description: String) -> Int {
        guard let range = description.range(of: "pid (\\d+)", options: .regularExpression) else { return 0 }
        let match = description[range]
        guard let pidStart = match.firstIndex(of: " ") else { return 0 }
        let pidStr = String(match[match.index(after: pidStart)..<match.index(before: match.endIndex)])
        return Int(pidStr) ?? 0
    }

    private nonisolated static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
