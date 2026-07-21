import Darwin
import Foundation

enum ProviderError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

final class SupervisorLocalProvider: ServiceManagerProvider, @unchecked Sendable {
    private let supervisorctlPath: String
    private let supervisorConfigPath: String?
    private let timeout: TimeInterval
    private let metricsSampler = LocalProcessMetricsSampler()

    init(supervisorctlPath: String, supervisorConfigPath: String? = nil, timeout: TimeInterval) {
        self.supervisorctlPath = supervisorctlPath
        self.supervisorConfigPath = supervisorConfigPath
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
        try await metricsSampler.sample(pid: pid)
    }

    private nonisolated func executeCommand(_ commandArguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
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
        args.append(contentsOf: commandArguments)
        process.arguments = args

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

private actor LocalProcessMetricsSampler {
    private struct Snapshot {
        let timestamp: Date
        let cpuNanoseconds: UInt64
    }

    private var snapshotsByPID: [Int: Snapshot] = [:]

    func sample(pid: Int) async throws -> ProcessMetrics {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "pcpu=,rss="]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let (stdout, exitCode) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(stdout: String, exitCode: Int32), Error>) in
            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                continuation.resume(with: .success((stdout, proc.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(with: .failure(error))
            }
        }

        guard exitCode == 0 else {
            throw ProviderError.commandFailed("Could not read process metrics for pid \(pid)")
        }

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
}
