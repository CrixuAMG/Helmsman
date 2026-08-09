import Foundation
import Observation

@Observable
final class ServiceManager {
    var services: [Service] = []
    var isConnected: Bool = false
    var activeProviderName: String?
    var lastError: Error?
    var isLoading: Bool = false
    var retryCount: Int = 0

    private let connection: Connection
    private var resolvedProvider: (any ServiceManagerProvider)?
    private let maxRetries = 3

    init(connection: Connection) {
        self.connection = connection
    }

    func refresh() async {
        await refresh(withRetry: true)
    }

    private func refresh(withRetry: Bool) async {
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
            retryCount = 0
        } catch {
            lastError = error
            isConnected = false
            activeProviderName = nil

            if withRetry && shouldRetry(error: error) && retryCount < maxRetries {
                retryCount += 1
                let delay = Double(retryCount) * 2.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await refresh(withRetry: true)
            }
        }
    }

    func start(_ service: Service) async throws {
        let controlName = service.controlName
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        do {
            try await provider.startProcess(controlName)
        } catch {
            if shouldReconnect(error: error) {
                resolvedProvider = nil
                let newProvider = try await resolveProvider()
                try await newProvider.startProcess(controlName)
            } else {
                throw error
            }
        }
    }

    func stop(_ service: Service) async throws {
        let controlName = service.controlName
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        do {
            try await provider.stopProcess(controlName)
        } catch {
            if shouldReconnect(error: error) {
                resolvedProvider = nil
                let newProvider = try await resolveProvider()
                try await newProvider.stopProcess(controlName)
            } else {
                throw error
            }
        }
    }

    func restart(_ service: Service) async throws {
        let controlName = service.controlName
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        do {
            try await provider.restartProcess(controlName)
        } catch {
            if shouldReconnect(error: error) {
                resolvedProvider = nil
                let newProvider = try await resolveProvider()
                try await newProvider.restartProcess(controlName)
            } else {
                throw error
            }
        }
    }

    func getProcessMetrics(pid: Int) async throws -> ProcessMetrics {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        return try await provider.getProcessMetrics(pid: pid)
    }

    func readProcessLog(controlName: String, stderr: Bool, offset: Int, maxBytes: Int) async throws -> ProcessLogChunk {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        do {
            return try await provider.readProcessLog(controlName, stderr: stderr, offset: offset, maxBytes: maxBytes)
        } catch {
            if shouldReconnect(error: error) {
                resolvedProvider = nil
                let newProvider = try await resolveProvider()
                return try await newProvider.readProcessLog(controlName, stderr: stderr, offset: offset, maxBytes: maxBytes)
            }
            throw error
        }
    }

    func clearProcessLogs(controlName: String) async throws {
        guard let provider = resolvedProvider else { throw ServiceError.providerUnavailable }
        do {
            try await provider.clearProcessLogs(controlName)
        } catch {
            if shouldReconnect(error: error) {
                resolvedProvider = nil
                let newProvider = try await resolveProvider()
                try await newProvider.clearProcessLogs(controlName)
            } else {
                throw error
            }
        }
    }

    func reconnect() async {
        resolvedProvider = nil
        retryCount = 0
        await refresh()
    }

    // MARK: - Error Handling

    private func shouldRetry(error: Error) -> Bool {
        if let connectionError = error as? ConnectionError {
            switch connectionError {
            case .timeout, .connectionRefused:
                return true
            default:
                return false
            }
        }

        if let serviceError = error as? ServiceError {
            switch serviceError {
            case .connectionLost:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        let networkCodes = [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost]
        return networkCodes.contains(nsError.code)
    }

    private func shouldReconnect(error: Error) -> Bool {
        if let serviceError = error as? ServiceError {
            return serviceError == .connectionLost
        }

        let nsError = error as NSError
        return nsError.code == NSURLErrorNetworkConnectionLost
    }

    // MARK: - Provider Resolution

    private func resolveProvider() async throws -> any ServiceManagerProvider {
        if let existing = resolvedProvider { return existing }

        let password = KeychainManager.retrievePassword(for: connection.id)
        let config = connection.makeProviderConfiguration(password: password)

        switch connection.connectionMethod {
        case .local:
            let provider = SupervisorLocalProvider(
                supervisorctlPath: config.supervisorctlPath,
                supervisorConfigPath: config.supervisorConfigPath,
                supervisorEndpoint: config.localEndpoint,
                timeout: config.timeout
            )
            resolvedProvider = provider
            activeProviderName = "Local"
            return provider

        case .docker:
            guard let container = config.dockerContainer, !container.isEmpty else {
                throw ConnectionError.invalidConfiguration("Docker container name is required")
            }
            let provider = try SupervisorDockerProvider(
                container: container,
                supervisorctlPath: config.supervisorctlPath,
                supervisorConfigPath: config.supervisorConfigPath,
                supervisorEndpoint: config.xmlrpcEndpoint ?? "http://127.0.0.1:9001/RPC2",
                username: config.username,
                password: config.password,
                timeout: config.timeout,
                dockerEndpoint: config.dockerEndpoint ?? dockerEndpoint(for: config)
            )
            resolvedProvider = provider
            activeProviderName = "Docker"
            return provider

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

        }
    }

    private func dockerEndpoint(for config: ProviderConfiguration) -> String {
        let host = config.host.isEmpty ? "127.0.0.1" : config.host
        let port = config.port == 0 ? 2375 : config.port
        return "http://\(host):\(port)"
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
        guard let endpointStr = config.xmlrpcEndpoint, let endpoint = URL(string: endpointStr) else {
            throw ConnectionError.invalidConfiguration("XML-RPC endpoint is required")
        }

        return SupervisorXMLRPCProvider(
            endpoint: endpoint,
            username: config.username,
            password: config.password,
            timeout: config.timeout
        )
    }
}
