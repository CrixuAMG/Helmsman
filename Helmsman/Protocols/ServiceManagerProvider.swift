import Foundation

struct ProcessLogChunk: Sendable, Equatable {
    let content: String
    /// Offset of the next unread byte. A value of `-1` means the provider
    /// returns a rolling tail window (no offset tracking possible).
    let nextOffset: Int

    static let rollingTail = ProcessLogChunk(content: "", nextOffset: -1)
}

protocol ServiceManagerProvider: Sendable {
    func getAllProcesses() async throws -> [SupervisorProcess]
    func startProcess(_ name: String) async throws
    func stopProcess(_ name: String) async throws
    func restartProcess(_ name: String) async throws
    func getProcessMetrics(pid: Int) async throws -> ProcessMetrics
    func readProcessLog(_ name: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk
    func clearProcessLogs(_ name: String) async throws
}

extension ServiceManagerProvider {
    func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        throw ProviderError.commandFailed("Metrics not supported for this connection type")
    }

    func readProcessLog(_ name: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk {
        throw ProviderError.commandFailed("Logs not supported for this connection type")
    }

    func clearProcessLogs(_ name: String) async throws {
        throw ProviderError.commandFailed("Clearing logs not supported for this connection type")
    }
}
