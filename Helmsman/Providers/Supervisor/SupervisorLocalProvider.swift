import Darwin
import Foundation

final class SupervisorLocalProvider: ServiceManagerProvider, @unchecked Sendable {
    private let endpoint: URL
    private let timeout: TimeInterval
    private let xmlrpcProvider: SupervisorXMLRPCProvider
    private let metricsSampler = LocalProcessMetricsSampler()

    init(localEndpoint: String = "http://127.0.0.1:9001/RPC2", timeout: TimeInterval) {
        self.endpoint = URL(string: localEndpoint) ?? URL(string: "http://127.0.0.1:9001/RPC2")!
        self.timeout = timeout
        self.xmlrpcProvider = SupervisorXMLRPCProvider(
            endpoint: self.endpoint,
            username: nil,
            password: nil,
            timeout: timeout
        )
    }

    nonisolated func getAllProcesses() async throws -> [SupervisorProcess] {
        try await xmlrpcProvider.getAllProcesses()
    }

    nonisolated func startProcess(_ name: String) async throws {
        try await xmlrpcProvider.startProcess(name)
    }

    nonisolated func stopProcess(_ name: String) async throws {
        try await xmlrpcProvider.stopProcess(name)
    }

    nonisolated func restartProcess(_ name: String) async throws {
        try await xmlrpcProvider.restartProcess(name)
    }

    nonisolated func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        try await metricsSampler.sample(pid: pid)
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
