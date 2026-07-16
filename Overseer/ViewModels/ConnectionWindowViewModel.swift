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
    var xmlrpcEndpoint: String = ""
    var connectionMethod: ConnectionMethod = .auto
    var pollingInterval: TimeInterval = 5
    var timeout: TimeInterval = 30
    var autoReconnect: Bool = true
    var safeMode: Bool = true
    var notes: String = ""

    private var connectionManager: ConnectionManager?

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
        isEditing = true
        populateForm(from: connection)
    }

    func newConnection() {
        selectedConnectionID = nil
        isEditing = true
        resetForm()
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
            existing.xmlrpcEndpoint = xmlrpcEndpoint.isEmpty ? nil : xmlrpcEndpoint
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
                xmlrpcEndpoint: xmlrpcEndpoint.isEmpty ? nil : xmlrpcEndpoint,
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
        xmlrpcEndpoint = connection.xmlrpcEndpoint ?? ""
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
        xmlrpcEndpoint = ""
        connectionMethod = .auto
        pollingInterval = 5
        timeout = 30
        autoReconnect = true
        safeMode = true
        notes = ""
    }
}
