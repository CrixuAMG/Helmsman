import Foundation

protocol ServiceManagerProvider: Sendable {
    func getAllProcesses() async throws -> [SupervisorProcess]
    func startProcess(_ name: String) async throws
    func stopProcess(_ name: String) async throws
    func restartProcess(_ name: String) async throws
    func getProcessMetrics(pid: Int) async throws -> ProcessMetrics
}

extension ServiceManagerProvider {
    func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        throw ProviderError.commandFailed("Metrics not supported for this connection type")
    }
}
