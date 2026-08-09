import Darwin
import Foundation

final class SupervisorLocalProvider: ServiceManagerProvider, @unchecked Sendable {
    private let supervisorctlPath: String
    private let supervisorConfigPath: String?
    private let supervisorEndpoint: String?
    private let metricsSampler = LocalProcessMetricsSampler()

    init(
        supervisorctlPath: String = "/usr/bin/supervisorctl",
        supervisorConfigPath: String? = nil,
        supervisorEndpoint: String? = nil,
        timeout: TimeInterval
    ) {
        self.supervisorctlPath = supervisorctlPath
        self.supervisorConfigPath = supervisorConfigPath
        self.supervisorEndpoint = supervisorEndpoint
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        let output = try await runSupervisorctl(["status"])
        return SupervisorSSHProvider.parseStatusOutput(output)
    }

    nonisolated func startProcess(_ name: String) async throws {
        let output = try await runSupervisorctl(["start", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func stopProcess(_ name: String) async throws {
        let output = try await runSupervisorctl(["stop", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func restartProcess(_ name: String) async throws {
        let output = try await runSupervisorctl(["restart", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        try await metricsSampler.sample(pid: pid)
    }

    nonisolated func readProcessLog(_ name: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk {
        let output = try await runTail(name: name, stderr: stderr, maxBytes: maxBytes)
        return ProcessLogChunk(content: output, nextOffset: -1)
    }

    nonisolated func clearProcessLogs(_ name: String) async throws {
        let output = try await runSupervisorctl(["clear", name])
        if output.contains("ERROR") {
            throw ProviderError.commandFailed(output)
        }
    }

    /// `supervisorctl tail` syntax differs between supervisor versions:
    /// - 3.x: `tail [-N bytes] name [stdout|stderr]`
    /// - 4.x: `tail [-n lines] [--stderr] name`
    private nonisolated func runTail(name: String, stderr: Bool, maxBytes: Int) async throws -> String {
        let variants: [[String]]
        if stderr {
            variants = [
                ["tail", "-\(maxBytes)", name, "stderr"],
                ["tail", "--stderr", name],
                ["tail", name, "stderr"],
            ]
        } else {
            variants = [
                ["tail", "-\(maxBytes)", name],
                ["tail", name],
            ]
        }

        var lastError: Error?
        for variant in variants {
            do {
                let output = try await runSupervisorctl(variant)
                if Self.isTailError(output) {
                    lastError = ProviderError.commandFailed(output)
                    continue
                }
                return output
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ProviderError.commandFailed("Unable to tail log for '\(name)'")
    }

    private nonisolated static func isTailError(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("Error") || trimmed.hasPrefix("ERROR") || trimmed.hasPrefix("error:")
    }

    private nonisolated func runSupervisorctl(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let executableURL = URL(fileURLWithPath: supervisorctlPath)
            process.executableURL = executableURL
            var commandArguments: [String] = []
            if let supervisorConfigPath, !supervisorConfigPath.isEmpty {
                commandArguments += ["-c", supervisorConfigPath]
            }
            // A config file may point to a Unix socket. Only override it with
            // an endpoint when no config file was supplied.
            if supervisorConfigPath == nil,
               let supervisorEndpoint,
               !supervisorEndpoint.isEmpty {
                commandArguments += ["-s", supervisorEndpoint]
            }
            process.arguments = commandArguments + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let fullOutput = output + errorOutput

                if process.terminationStatus == 0 {
                    continuation.resume(returning: fullOutput)
                } else {
                    continuation.resume(throwing: ProviderError.commandFailed(fullOutput))
                }
            }

            do {
                try process.run()
            } catch {
                let path = supervisorctlPath
                continuation.resume(throwing: ProviderError.commandFailed(
                    "Unable to start supervisorctl at '\(path)'. Check the path and grant Helmsman access to the executable. Under macOS App Sandbox, use the Browse button to select it."
                ))
            }
        }
    }
}

private actor LocalProcessMetricsSampler {
    func sample(pid: Int) async throws -> ProcessMetrics {
        guard let metrics = try? sampleMetrics(pid: pid) else {
            return ProcessMetrics(timestamp: Date(), cpuPercent: 0, memoryMB: 0)
        }
        return metrics
    }

    private func sampleMetrics(pid: Int) throws -> ProcessMetrics {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: Int8.self, capacity: size) { bytePtr in
                proc_pidinfo(Int32(pid), PROC_PIDTASKINFO, 0, bytePtr, Int32(size))
            }
        }
        guard result >= Int32(size) else {
            throw ProviderError.commandFailed("Could not read process info for pid \(pid)")
        }

        let cpuNS = taskInfo.pti_total_user + taskInfo.pti_total_system
        let uptime = ProcessInfo.processInfo.systemUptime
        let cpuPercent = uptime > 0 ? (Double(cpuNS) / 1_000_000_000.0 / uptime * 100.0) : 0
        let memoryMB = Double(taskInfo.pti_resident_size) / (1024.0 * 1024.0)

        return ProcessMetrics(timestamp: Date(), cpuPercent: cpuPercent, memoryMB: memoryMB)
    }
}
