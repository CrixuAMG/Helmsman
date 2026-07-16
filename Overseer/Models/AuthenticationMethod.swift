import Foundation

enum AuthenticationMethod: String, Codable, CaseIterable, Sendable {
    case sshKey
    case password

    var displayName: String {
        switch self {
        case .sshKey: "SSH Key"
        case .password: "Password"
        }
    }
}
