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
        let (stdout, _) = try await executeRemotely("status")
        return Self.parseStatusOutput(stdout)
    }

    nonisolated func startProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeRemotely("start \(Self.shellEscape(name))")
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeRemotely("stop \(Self.shellEscape(name))")
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeRemotely("restart \(Self.shellEscape(name))")
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        let (stdout, exitCode) = try await executeRaw("ps -p \(pid) -o %cpu=,rss=")
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }

        let parts = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let rssKB = Double(parts[1]) else {
            throw ProviderError.commandFailed("Could not parse metrics: \(stdout)")
        }

        return ProcessMetrics(
            timestamp: Date(),
            cpuPercent: cpu,
            memoryMB: rssKB / 1024.0
        )
    }

    // MARK: - SSH Execution

    private nonisolated func executeRemotely(_ command: String) async throws -> (stdout: String, exitCode: Int32) {
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

            let resumeOnce: @Sendable (Result<(stdout: String, exitCode: Int32), Error>) -> Void = { result in
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
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let output = stdout.isEmpty ? stderr : stdout

                resumeOnce(.success((output, proc.terminationStatus)))
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

    private nonisolated func executeRaw(_ command: String) async throws -> (stdout: String, exitCode: Int32) {
        var sshArgs = buildSSHArguments()
        sshArgs.append(command)

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

            let resumeOnce: @Sendable (Result<(stdout: String, exitCode: Int32), Error>) -> Void = { result in
                lock.lock()
                guard !resumed.value else { lock.unlock(); return }
                resumed.value = true
                lock.unlock()
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                resumeOnce(.success((stdout, proc.terminationStatus)))
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
                uptime: extractUptime(from: description),
                exitStatus: nil
            )
        }
        return SupervisorProcess(
            name: fullName,
            group: fullName,
            status: status,
            description: description,
            pid: extractPid(from: description),
            uptime: extractUptime(from: description),
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
        let pidStr = String(match[match.index(after: pidStart)..<match.endIndex])
        return Int(pidStr) ?? 0
    }

    private nonisolated static func extractUptime(from description: String) -> TimeInterval? {
        guard let uptimeRange = description.range(of: "uptime ") else { return nil }
        let uptimeStr = String(description[uptimeRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        var totalSeconds: TimeInterval = 0

        if let dayMatch = uptimeStr.range(of: "(\\d+)\\s+day", options: .regularExpression) {
            let dayStr = String(uptimeStr[dayMatch])
            if let days = dayStr.split(separator: " ").first.map({ Int($0) ?? 0 }) {
                totalSeconds += TimeInterval(days * 86400)
            }
        }

        if let timeRange = uptimeStr.range(of: "\\d+:\\d+:\\d+$", options: .regularExpression) {
            let timeStr = String(uptimeStr[timeRange])
            let components = timeStr.split(separator: ":")
            if components.count == 3,
               let hours = Int(components[0]),
               let minutes = Int(components[1]),
               let seconds = Int(components[2]) {
                totalSeconds += TimeInterval(hours * 3600 + minutes * 60 + seconds)
            }
        } else if let timeRange = uptimeStr.range(of: "\\d+:\\d+$", options: .regularExpression) {
            let timeStr = String(uptimeStr[timeRange])
            let components = timeStr.split(separator: ":")
            if components.count == 2,
               let minutes = Int(components[0]),
               let seconds = Int(components[1]) {
                totalSeconds += TimeInterval(minutes * 60 + seconds)
            }
        }

        return totalSeconds > 0 ? totalSeconds : nil
    }

    private nonisolated static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
