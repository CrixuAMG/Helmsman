import Foundation

enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    case local
    case docker
    case ssh
    case xmlrpc

    var displayName: String {
        switch self {
        case .local: "Local"
        case .docker: "Docker"
        case .ssh: "SSH"
        case .xmlrpc: "XML-RPC"
        }
    }
}
