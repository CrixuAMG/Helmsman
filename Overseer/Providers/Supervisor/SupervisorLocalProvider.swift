import Foundation

final class SupervisorLocalProvider: ServiceManagerProvider, @unchecked Sendable {
    private let supervisorctlPath: String
    private let supervisorConfigPath: String?
    private let timeout: TimeInterval

    init(supervisorctlPath: String, supervisorConfigPath: String? = nil, timeout: TimeInterval) {
        self.supervisorctlPath = supervisorctlPath
        self.supervisorConfigPath = supervisorConfigPath
        self.timeout = timeout
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let output = try await executeCommand("status")
        return SupervisorSSHProvider.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        _ = try await executeCommand("start \(name)")
    }

    nonisolated func stopProcess(_ name: String) async throws {
        _ = try await executeCommand("stop \(name)")
    }

    nonisolated func restartProcess(_ name: String) async throws {
        _ = try await executeCommand("restart \(name)")
    }

    private nonisolated func executeCommand(_ command: String) async throws -> String {
        let resolvedPath: String
        if FileManager.default.fileExists(atPath: supervisorctlPath) {
            resolvedPath = supervisorctlPath
        } else if let found = await SupervisorctlFinder.find() {
            resolvedPath = found
        } else {
            throw ConnectionError.invalidConfiguration("supervisorctl not found. Install it or specify the correct path.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        
        var args: [String] = []
        if let configPath = supervisorConfigPath {
            args.append(contentsOf: ["-c", configPath])
        }
        args.append(contentsOf: command.split(separator: " ").map(String.init))
        process.arguments = args

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

    private nonisolated static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
