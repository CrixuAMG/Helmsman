import Foundation
import SwiftData
import SwiftUI

@Model
final class Connection {
    var id: UUID
    var name: String
    var accentColorHex: String
    var host: String
    var port: Int
    var username: String
    var authenticationMethodRaw: String
    var sshKeyPath: String?
    var supervisorctlPath: String
    var xmlrpcEndpoint: String?
    var dockerContainer: String?
    var connectionMethodRaw: String
    var pollingInterval: TimeInterval
    var timeout: TimeInterval
    var autoReconnect: Bool
    var safeMode: Bool
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    var authenticationMethod: AuthenticationMethod {
        get { AuthenticationMethod(rawValue: authenticationMethodRaw) ?? .sshKey }
        set { authenticationMethodRaw = newValue.rawValue }
    }

    var connectionMethod: ConnectionMethod {
        get { ConnectionMethod(rawValue: connectionMethodRaw) ?? .auto }
        set { connectionMethodRaw = newValue.rawValue }
    }

    var accentColor: Color {
        get { Color(hex: accentColorHex) ?? .blue }
        set { accentColorHex = newValue.toHex() ?? "#007AFF" }
    }

    init(
        name: String,
        accentColorHex: String = "#007AFF",
        host: String = "localhost",
        port: Int = 22,
        username: String = "",
        authenticationMethod: AuthenticationMethod = .sshKey,
        sshKeyPath: String? = nil,
        supervisorctlPath: String = "/usr/bin/supervisorctl",
        xmlrpcEndpoint: String? = nil,
        dockerContainer: String? = nil,
        connectionMethod: ConnectionMethod = .auto,
        pollingInterval: TimeInterval = 5,
        timeout: TimeInterval = 30,
        autoReconnect: Bool = true,
        safeMode: Bool = true,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.accentColorHex = accentColorHex
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMethodRaw = authenticationMethod.rawValue
        self.sshKeyPath = sshKeyPath
        self.supervisorctlPath = supervisorctlPath
        self.xmlrpcEndpoint = xmlrpcEndpoint
        self.dockerContainer = dockerContainer
        self.connectionMethodRaw = connectionMethod.rawValue
        self.pollingInterval = pollingInterval
        self.timeout = timeout
        self.autoReconnect = autoReconnect
        self.safeMode = safeMode
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func makeProviderConfiguration(password: String? = nil) -> ProviderConfiguration {
        ProviderConfiguration(
            host: host,
            port: port,
            username: username,
            authenticationMethod: authenticationMethod,
            sshKeyPath: sshKeyPath,
            password: password,
            supervisorctlPath: supervisorctlPath,
            xmlrpcEndpoint: xmlrpcEndpoint,
            dockerContainer: dockerContainer,
            timeout: timeout
        )
    }
}
