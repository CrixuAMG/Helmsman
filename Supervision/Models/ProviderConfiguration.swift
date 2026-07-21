import Foundation

struct ProviderConfiguration: Sendable {
    let host: String
    let port: Int
    let username: String
    let authenticationMethod: AuthenticationMethod
    let sshKeyPath: String?
    let password: String?
    let supervisorctlPath: String
    let supervisorConfigPath: String?
    let xmlrpcEndpoint: String?
    let dockerContainer: String?
    let timeout: TimeInterval
}
