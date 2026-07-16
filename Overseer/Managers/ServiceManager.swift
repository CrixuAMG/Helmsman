import Foundation
import Observation

@Observable
final class ServiceManager {
    var services: [Service] = []
    var isConnected: Bool = false
    var activeProviderName: String?
    var lastError: Error?
    var isLoading: Bool = false

    private let connection: Connection
    private var resolvedProvider: (any ServiceManagerProvider)?

    init(connection: Connection) {
        self.connection = connection
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let provider = try await resolveProvider()
            let processes = try await provider.getAllProcesses()
            services = processes.map { process in
                Service(
                    name: process.name,
                    group: process.group,
                    status: process.status,
                    description: process.description,
                    pid: process.pid,
                    uptime: process.uptime,
                    exitStatus: process.exitStatus,
                    lastUpdated: Date()
                )
            }
            isConnected = true
            lastError = nil
        } catch {
            lastError = error
            isConnected = false
        }
    }

    func start(_ service: Service) async throws {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        try await provider.startProcess(service.name)
    }

    func stop(_ service: Service) async throws {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        try await provider.stopProcess(service.name)
    }

    func restart(_ service: Service) async throws {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        try await provider.restartProcess(service.name)
    }

    // MARK: - Provider Resolution

    private func resolveProvider() async throws -> any ServiceManagerProvider {
        if let existing = resolvedProvider { return existing }

        let password = KeychainManager.retrievePassword(for: connection.id)
        let config = connection.makeProviderConfiguration(password: password)

        switch connection.connectionMethod {
        case .ssh:
            let provider = try await createSSHProvider(config: config)
            resolvedProvider = provider
            activeProviderName = "SSH"
            return provider

        case .xmlrpc:
            let provider = try await createXMLRPCProvider(config: config)
            resolvedProvider = provider
            activeProviderName = "XML-RPC"
            return provider

        case .auto:
            do {
                let provider = try await createXMLRPCProvider(config: config)
                _ = try await provider.getAllProcesses()
                resolvedProvider = provider
                activeProviderName = "XML-RPC"
                return provider
            } catch {
                let provider = try await createSSHProvider(config: config)
                resolvedProvider = provider
                activeProviderName = "SSH"
                return provider
            }
        }
    }

    private func createSSHProvider(config: ProviderConfiguration) async throws -> any ServiceManagerProvider {
        SupervisorSSHProvider(
            host: config.host,
            port: config.port,
            username: config.username,
            authenticationMethod: config.authenticationMethod,
            sshKeyPath: config.sshKeyPath,
            password: config.password,
            supervisorctlPath: config.supervisorctlPath,
            timeout: config.timeout
        )
    }

    private func createXMLRPCProvider(config: ProviderConfiguration) async throws -> any ServiceManagerProvider {
        throw ServiceError.providerUnavailable
    }
}
