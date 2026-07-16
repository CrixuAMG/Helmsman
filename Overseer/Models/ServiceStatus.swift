import Foundation

enum ServiceStatus: String, Codable, CaseIterable, Sendable {
    case running
    case stopped
    case starting
    case backingoff
    case stopping
    case exited
    case fatal
    case unknown

    var displayName: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .backingoff: "Backing Off"
        case .stopping: "Stopping"
        case .exited: "Exited"
        case .fatal: "Fatal"
        case .unknown: "Unknown"
        }
    }
}
