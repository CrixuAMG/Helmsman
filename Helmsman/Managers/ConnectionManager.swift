import Foundation
import SwiftData

@Observable
final class ConnectionManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(_ connection: Connection) {
        modelContext.insert(connection)
        try? modelContext.save()
    }

    func update(_ connection: Connection) {
        connection.updatedAt = Date()
        try? modelContext.save()
    }

    func delete(_ connection: Connection) {
        modelContext.delete(connection)
        try? modelContext.save()
    }

    func duplicate(_ connection: Connection) -> Connection {
        let copy = Connection(
            name: "\(connection.name) (Copy)",
            accentColorHex: connection.accentColorHex,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            authenticationMethod: connection.authenticationMethod,
            sshKeyPath: connection.sshKeyPath,
            supervisorctlPath: connection.supervisorctlPath,
            supervisorConfigPath: connection.supervisorConfigPath,
            xmlrpcEndpoint: connection.xmlrpcEndpoint,
            localEndpoint: connection.localEndpoint,
            dockerContainer: connection.dockerContainer,
            connectionMethod: connection.connectionMethod,
            pollingInterval: connection.pollingInterval,
            timeout: connection.timeout,
            autoReconnect: connection.autoReconnect,
            safeMode: connection.safeMode,
            notes: connection.notes
        )
        modelContext.insert(copy)
        try? modelContext.save()
        return copy
    }
}
