import Foundation

final class SupervisorDockerProvider: ServiceManagerProvider, @unchecked Sendable {
    private let container: String
    private let supervisorctlPath: String
    private let timeout: TimeInterval

    init(container: String, supervisorctlPath: String, timeout: TimeInterval) {
        self.container = container
        self.supervisorctlPath = supervisorctlPath
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
        guard FileManager.default.fileExists(atPath: "/usr/bin/docker") else {
            throw ConnectionError.invalidConfiguration("Docker not found at /usr/bin/docker")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/docker")
        process.arguments = ["exec", container, supervisorctlPath] + command.split(separator: " ").map(String.init)

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
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    resumeOnce(.success(stdout))
                } else {
                    let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                        : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    resumeOnce(.failure(ServiceError.actionFailed(message)))
                }
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
}
