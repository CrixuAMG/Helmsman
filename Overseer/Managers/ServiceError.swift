import Foundation

enum ServiceError: LocalizedError {
    case notFound(String)
    case alreadyRunning(String)
    case alreadyStopped(String)
    case actionFailed(String)
    case providerUnavailable
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            "Service '\(name)' not found"
        case .alreadyRunning(let name):
            "Service '\(name)' is already running"
        case .alreadyStopped(let name):
            "Service '\(name)' is already stopped"
        case .actionFailed(let reason):
            "Action failed: \(reason)"
        case .providerUnavailable:
            "No service provider available"
        case .connectionLost:
            "Connection to host was lost"
        }
    }
}
