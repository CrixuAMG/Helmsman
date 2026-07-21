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
        let (stdout, _) = try await executeCommand(["status"])
        return SupervisorSSHProvider.parseStatusOutput(stdout)
    }

    nonisolated func startProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeCommand(["start", name])
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeCommand(["stop", name])
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        let (stdout, exitCode) = try await executeCommand(["restart", name])
        guard exitCode == 0 else { throw ProviderError.commandFailed(stdout) }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = dockerPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ConnectionError.invalidConfiguration("Docker not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["exec", container, "ps", "-p", "\(pid)", "-o", "%cpu=," + "rss="]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (stdout, exitCode) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(stdout: String, exitCode: Int32), Error>) in
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

    private nonisolated func executeCommand(_ commandArguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        guard let dockerPath = dockerPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ConnectionError.invalidConfiguration("Docker not found. Install Docker or specify the path in your connection settings.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["exec", container, supervisorctlPath] + commandArguments

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
}
