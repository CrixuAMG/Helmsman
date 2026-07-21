import Foundation

enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    case local
    case docker
    case auto
    case ssh
    case xmlrpc

    var displayName: String {
        switch self {
        case .local: "Local"
        case .docker: "Docker"
        case .auto: "Auto"
        case .ssh: "SSH"
        case .xmlrpc: "XML-RPC"
        }
    }
}
