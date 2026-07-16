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
        let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = dockerPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ConnectionError.invalidConfiguration("Docker not found. Install Docker or specify the path in your connection settings.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
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
}
