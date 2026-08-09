import Foundation

enum ProcessEventKind: String, Codable, Sendable {
    case started
    case running
    case stopped
    case crashed
    case restarted
    case exited
    case fatal
    case backingoff
    case unknown

    var displayName: String {
        switch self {
        case .started: "Started"
        case .running: "Running"
        case .stopped: "Stopped"
        case .crashed: "Crashed"
        case .restarted: "Restart"
        case .exited: "Exited"
        case .fatal: "Fatal"
        case .backingoff: "Backing Off"
        case .unknown: "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .started: "play.circle.fill"
        case .running: "arrow.clockwise.circle.fill"
        case .stopped: "stop.circle.fill"
        case .crashed, .fatal: "exclamationmark.triangle.fill"
        case .restarted: "arrow.clockwise.circle.fill"
        case .exited: "xmark.circle.fill"
        case .backingoff: "hourglass.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct ProcessEvent: Identifiable, Sendable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: ProcessEventKind
    let detail: String
}
