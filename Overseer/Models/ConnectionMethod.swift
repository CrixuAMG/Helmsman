import Foundation

enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    case auto
    case ssh
    case xmlrpc

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .ssh: "SSH"
        case .xmlrpc: "XML-RPC"
        }
    }
}
