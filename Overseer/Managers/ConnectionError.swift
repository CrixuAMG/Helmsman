import Foundation

enum ConnectionError: LocalizedError {
    case notFound
    case authenticationFailed
    case timeout
    case connectionRefused
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Connection not found"
        case .authenticationFailed:
            "Authentication failed"
        case .timeout:
            "Connection timed out"
        case .connectionRefused:
            "Connection refused"
        case .invalidConfiguration(let reason):
            "Invalid configuration: \(reason)"
        }
    }
}
