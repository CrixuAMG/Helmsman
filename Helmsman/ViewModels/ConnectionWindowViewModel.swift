import Foundation
import Observation

@Observable
final class ConnectionWindowViewModel {
    var connections: [Connection] = []
    var selectedConnectionID: UUID?
    var isEditing = false

    var name = ""
    var accentColorHex = "#007AFF"
    var host = ""
    var port = 22
    var username = ""
    var authenticationMethod: AuthenticationMethod = .sshKey
    var sshKeyPath = ""
    var password = ""
    var supervisorctlPath = "/usr/bin/supervisorctl"
    var supervisorConfigPath = ""
    var xmlrpcEndpoint = ""
    var localEndpoint = "http://127.0.0.1:9001/RPC2"
    var dockerContainer = ""
    var connectionMethod: ConnectionMethod = .auto
    var pollingInterval: TimeInterval = 5
    var timeout: TimeInterval = 30
    var autoReconnect = true
    var safeMode = true
    var touchIDProtected = false
    var notes = ""

    var isTesting = false
    var testResult: TestResult?

    var isFormValid: Bool {
        guard !name.isEmpty else { return false }

        switch connectionMethod {
        case .local:
            return URL(string: localEndpoint) != nil
        case .docker:
            return !host.isEmpty && port > 0 && !dockerContainer.isEmpty && !supervisorctlPath.isEmpty
        case .ssh:
            return !host.isEmpty && port > 0 && !username.isEmpty && !supervisorctlPath.isEmpty && hasValidSSHCredentials
        case .xmlrpc, .auto:
            return URL(string: xmlrpcEndpoint) != nil
        }
    }

    private var connectionManager: ConnectionManager?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    func setConnectionManager(_ manager: ConnectionManager) {
        connectionManager = manager
    }

    func loadConnections(_ connections: [Connection]) {
        self.connections = connections
    }

    func selectConnection(_ connection: Connection?) {
        guard let connection else {
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

        if let existing = selectedConnection {
            update(existing)
            manager.update(existing)
            savePassword(for: existing)
        } else {
            let connection = makeConnection()
            manager.create(connection)
            savePassword(for: connection)
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

    func connectionMethodChanged() {
        testResult = nil

        switch connectionMethod {
        case .local:
            host = ""
            port = 0
            if localEndpoint.isEmpty {
                localEndpoint = "http://127.0.0.1:9001/RPC2"
            }
        case .docker:
            if host.isEmpty { host = "127.0.0.1" }
            if port == 0 || port == 22 { port = 2375 }
            username = ""
            password = ""
        case .ssh:
            if host == "127.0.0.1" { host = "" }
            if port == 0 || port == 2375 { port = 22 }
        case .xmlrpc, .auto:
            host = ""
            port = 0
            if xmlrpcEndpoint.isEmpty {
                xmlrpcEndpoint = "http://localhost:9001/RPC2"
            }
        }
    }

    func testConnection() async {
        isTesting = true
        testResult = nil

        do {
            let provider = try makeTestProvider()
            let processes = try await provider.getAllProcesses()
            testResult = .success("Connected successfully. Found \(processes.count) service(s).")
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }

    private var selectedConnection: Connection? {
        guard let selectedConnectionID else { return nil }
        return connections.first { $0.id == selectedConnectionID }
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
        localEndpoint = connection.localEndpoint ?? "http://127.0.0.1:9001/RPC2"
        dockerContainer = connection.dockerContainer ?? ""
        connectionMethod = connection.connectionMethod
        pollingInterval = connection.pollingInterval
        timeout = connection.timeout
        autoReconnect = connection.autoReconnect
        safeMode = connection.safeMode
        touchIDProtected = connection.touchIDProtected
        notes = connection.notes ?? ""
    }

    private func resetForm() {
        name = ""
        accentColorHex = "#007AFF"
        host = ""
        port = 0
        username = ""
        authenticationMethod = .sshKey
        sshKeyPath = ""
        password = ""
        supervisorctlPath = "/usr/bin/supervisorctl"
        supervisorConfigPath = ""
        xmlrpcEndpoint = "http://localhost:9001/RPC2"
        localEndpoint = ""
        dockerContainer = ""
        connectionMethod = .auto
        pollingInterval = 5
        timeout = 30
        autoReconnect = true
        safeMode = true
        touchIDProtected = false
        notes = ""
    }

    private func makeConnection() -> Connection {
        Connection(
            name: name,
            accentColorHex: accentColorHex,
            host: host,
            port: port,
            username: username,
            authenticationMethod: authenticationMethod,
            sshKeyPath: optionalText(sshKeyPath),
            supervisorctlPath: supervisorctlPath,
            supervisorConfigPath: optionalText(supervisorConfigPath),
            xmlrpcEndpoint: optionalText(xmlrpcEndpoint),
            localEndpoint: optionalText(localEndpoint),
            dockerContainer: optionalText(dockerContainer),
            connectionMethod: connectionMethod,
            pollingInterval: pollingInterval,
            timeout: timeout,
            autoReconnect: autoReconnect,
            safeMode: safeMode,
            touchIDProtected: touchIDProtected,
            notes: optionalText(notes)
        )
    }

    private func update(_ connection: Connection) {
        connection.name = name
        connection.accentColorHex = accentColorHex
        connection.host = host
        connection.port = port
        connection.username = username
        connection.authenticationMethod = authenticationMethod
        connection.sshKeyPath = optionalText(sshKeyPath)
        connection.supervisorctlPath = supervisorctlPath
        connection.supervisorConfigPath = optionalText(supervisorConfigPath)
        connection.xmlrpcEndpoint = optionalText(xmlrpcEndpoint)
        connection.localEndpoint = optionalText(localEndpoint)
        connection.dockerContainer = optionalText(dockerContainer)
        connection.connectionMethod = connectionMethod
        connection.pollingInterval = pollingInterval
        connection.timeout = timeout
        connection.autoReconnect = autoReconnect
        connection.safeMode = safeMode
        connection.touchIDProtected = touchIDProtected
        connection.notes = optionalText(notes)
    }

    private func makeProviderConfiguration() -> ProviderConfiguration {
        ProviderConfiguration(
            host: host,
            port: port,
            username: username,
            authenticationMethod: authenticationMethod,
            sshKeyPath: optionalText(sshKeyPath),
            password: optionalText(password),
            supervisorctlPath: supervisorctlPath,
            supervisorConfigPath: optionalText(supervisorConfigPath),
            xmlrpcEndpoint: optionalText(xmlrpcEndpoint),
            localEndpoint: optionalText(localEndpoint),
            dockerContainer: optionalText(dockerContainer),
            timeout: timeout
        )
    }

    private func makeTestProvider() throws -> any ServiceManagerProvider {
        let config = makeProviderConfiguration()

        switch connectionMethod {
        case .local:
            return SupervisorLocalProvider(
                supervisorctlPath: config.supervisorctlPath,
                timeout: config.timeout
            )
        case .docker:
            guard let container = config.dockerContainer, !container.isEmpty else {
                throw ConnectionError.invalidConfiguration("Docker container name is required")
            }
            return SupervisorDockerProvider(
                container: container,
                supervisorctlPath: config.supervisorctlPath,
                timeout: config.timeout,
                dockerEndpoint: dockerEndpoint(for: config)
            )
        case .ssh:
            return SupervisorSSHProvider(
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
            guard let endpointString = config.xmlrpcEndpoint,
                  let endpoint = URL(string: endpointString) else {
                throw ConnectionError.invalidConfiguration("Valid XML-RPC endpoint is required")
            }
            return SupervisorXMLRPCProvider(
                endpoint: endpoint,
                username: config.username,
                password: config.password,
                timeout: config.timeout
            )
        case .auto:
            throw ConnectionError.invalidConfiguration("Please select a specific connection method to test")
        }
    }

    private var hasValidSSHCredentials: Bool {
        switch authenticationMethod {
        case .sshKey:
            return !sshKeyPath.isEmpty
        case .password:
            return !password.isEmpty
        }
    }

    private func dockerEndpoint(for config: ProviderConfiguration) -> String {
        let dockerHost = config.host.isEmpty ? "127.0.0.1" : config.host
        let dockerPort = config.port == 0 ? 2375 : config.port
        return "http://\(dockerHost):\(dockerPort)"
    }

    private func savePassword(for connection: Connection) {
        guard !password.isEmpty else { return }

        let shouldSavePassword = connectionMethod == .xmlrpc
            || connectionMethod == .auto
            || (connectionMethod == .ssh && authenticationMethod == .password)

        if shouldSavePassword {
            try? KeychainManager.store(password: password, for: connection.id)
        }
    }

    private func optionalText(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}
