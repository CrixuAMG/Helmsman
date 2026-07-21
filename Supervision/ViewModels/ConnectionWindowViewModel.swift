import Foundation
import Observation

@Observable
final class ConnectionWindowViewModel {
    var connections: [Connection] = []
    var selectedConnectionID: UUID?
    var isEditing: Bool = false

    var name: String = ""
    var accentColorHex: String = "#007AFF"
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authenticationMethod: AuthenticationMethod = .sshKey
    var sshKeyPath: String = ""
    var password: String = ""
    var supervisorctlPath: String = "/usr/bin/supervisorctl"
    var supervisorConfigPath: String = ""
    var xmlrpcEndpoint: String = ""
    var dockerContainer: String = ""
    var connectionMethod: ConnectionMethod = .auto
    var pollingInterval: TimeInterval = 5
    var timeout: TimeInterval = 30
    var autoReconnect: Bool = true
    var safeMode: Bool = true
    var notes: String = ""

    var isTesting: Bool = false
    var testResult: TestResult?

    private var connectionManager: ConnectionManager?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    func setConnectionManager(_ manager: ConnectionManager) {
        self.connectionManager = manager
    }

    func loadConnections(_ connections: [Connection]) {
        self.connections = connections
    }

    func selectConnection(_ connection: Connection?) {
        guard let connection = connection else {
            selectedConnectionID = nil
            isEditing = false
            resetForm()
            return
        }
        selectedConnectionID = connection.id
        isEditing = false
        populateForm(from: connection)
    }

    func editConnection(_ connection: Connection) {
        selectedConnectionID = connection.id
        isEditing = true
        populateForm(from: connection)
    }

    func newConnection() {
        selectedConnectionID = nil
        isEditing = true
        resetForm()
        Task { await detectSupervisorctlPath() }
    }

    func save() {
        guard let manager = connectionManager else { return }

        if let id = selectedConnectionID, let existing = connections.first(where: { $0.id == id }) {
            existing.name = name
            existing.accentColorHex = accentColorHex
            existing.host = host
            existing.port = port
            existing.username = username
            existing.authenticationMethod = authenticationMethod
            existing.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
            existing.supervisorctlPath = supervisorctlPath
            existing.supervisorConfigPath = supervisorConfigPath.isEmpty ? nil : supervisorConfigPath
            existing.xmlrpcEndpoint = xmlrpcEndpoint.isEmpty ? nil : xmlrpcEndpoint
            existing.dockerContainer = dockerContainer.isEmpty ? nil : dockerContainer
            existing.connectionMethod = connectionMethod
            existing.pollingInterval = pollingInterval
            existing.timeout = timeout
            existing.autoReconnect = autoReconnect
            existing.safeMode = safeMode
            existing.notes = notes.isEmpty ? nil : notes
            manager.update(existing)

            if authenticationMethod == .password && !password.isEmpty {
                try? KeychainManager.store(password: password, for: existing.id)
            }
        } else {
            let connection = Connection(
                name: name,
                accentColorHex: accentColorHex,
                host: host,
                port: port,
                username: username,
                authenticationMethod: authenticationMethod,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
                supervisorctlPath: supervisorctlPath,
                supervisorConfigPath: supervisorConfigPath.isEmpty ? nil : supervisorConfigPath,
                xmlrpcEndpoint: xmlrpcEndpoint.isEmpty ? nil : xmlrpcEndpoint,
                dockerContainer: dockerContainer.isEmpty ? nil : dockerContainer,
                connectionMethod: connectionMethod,
                pollingInterval: pollingInterval,
                timeout: timeout,
                autoReconnect: autoReconnect,
                safeMode: safeMode,
                notes: notes.isEmpty ? nil : notes
            )
            manager.create(connection)

            if authenticationMethod == .password && !password.isEmpty {
                try? KeychainManager.store(password: password, for: connection.id)
            }
        }
    }

    func delete(_ connection: Connection) {
        guard let manager = connectionManager else { return }
        KeychainManager.deletePassword(for: connection.id)
        manager.delete(connection)
        if selectedConnectionID == connection.id {
            selectedConnectionID = nil
            isEditing = false
            resetForm()
        }
    }

    func duplicate(_ connection: Connection) {
        _ = connectionManager?.duplicate(connection)
    }

    func detectSupervisorctlPath() async {
        if let path = await SupervisorctlFinder.find() {
            supervisorctlPath = path
        }
    }

    func testConnection() async {
        isTesting = true
        testResult = nil

        let config = ProviderConfiguration(
            host: host,
            port: port,
            username: username,
            authenticationMethod: authenticationMethod,
            sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
            password: password.isEmpty ? nil : password,
            supervisorctlPath: supervisorctlPath,
            supervisorConfigPath: supervisorConfigPath.isEmpty ? nil : supervisorConfigPath,
            xmlrpcEndpoint: xmlrpcEndpoint.isEmpty ? nil : xmlrpcEndpoint,
            dockerContainer: dockerContainer.isEmpty ? nil : dockerContainer,
            timeout: timeout
        )

        do {
            let provider: any ServiceManagerProvider

            switch connectionMethod {
            case .local:
                provider = SupervisorLocalProvider(
                    supervisorctlPath: config.supervisorctlPath,
                    supervisorConfigPath: config.supervisorConfigPath,
                    timeout: config.timeout
                )
            case .docker:
                guard let container = config.dockerContainer, !container.isEmpty else {
                    testResult = .failure("Docker container name is required")
                    isTesting = false
                    return
                }
                provider = SupervisorDockerProvider(
                    container: container,
                    supervisorctlPath: config.supervisorctlPath,
                    timeout: config.timeout
                )
            case .ssh:
                provider = SupervisorSSHProvider(
                    host: config.host,
                    port: config.port,
                    username: config.username,
                    authenticationMethod: config.authenticationMethod,
                    sshKeyPath: config.sshKeyPath,
                    password: config.password,
                    supervisorctlPath: config.supervisorctlPath,
                    timeout: config.timeout
                )
            case .xmlrpc:
                guard let endpointStr = config.xmlrpcEndpoint, let endpoint = URL(string: endpointStr) else {
                    testResult = .failure("Valid XML-RPC endpoint is required")
                    isTesting = false
                    return
                }
                provider = SupervisorXMLRPCProvider(
                    endpoint: endpoint,
                    username: config.username,
                    password: config.password,
                    timeout: config.timeout
                )
            case .auto:
                testResult = .failure("Please select a specific connection method to test")
                isTesting = false
                return
            }

            let processes = try await provider.getAllProcesses()
            testResult = .success("Connected successfully. Found \(processes.count) service(s).")
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }

    private func populateForm(from connection: Connection) {
        name = connection.name
        accentColorHex = connection.accentColorHex
        host = connection.host
        port = connection.port
        username = connection.username
        authenticationMethod = connection.authenticationMethod
        sshKeyPath = connection.sshKeyPath ?? ""
        password = KeychainManager.retrievePassword(for: connection.id) ?? ""
        supervisorctlPath = connection.supervisorctlPath
        supervisorConfigPath = connection.supervisorConfigPath ?? ""
        xmlrpcEndpoint = connection.xmlrpcEndpoint ?? ""
        dockerContainer = connection.dockerContainer ?? ""
        connectionMethod = connection.connectionMethod
        pollingInterval = connection.pollingInterval
        timeout = connection.timeout
        autoReconnect = connection.autoReconnect
        safeMode = connection.safeMode
        notes = connection.notes ?? ""
    }

    private func resetForm() {
        name = ""
        accentColorHex = "#007AFF"
        host = ""
        port = 22
        username = ""
        authenticationMethod = .sshKey
        sshKeyPath = ""
        password = ""
        supervisorctlPath = "/usr/bin/supervisorctl"
        supervisorConfigPath = ""
        xmlrpcEndpoint = ""
        dockerContainer = ""
        connectionMethod = .auto
        pollingInterval = 5
        timeout = 30
        autoReconnect = true
        safeMode = true
        notes = ""
    }
}
