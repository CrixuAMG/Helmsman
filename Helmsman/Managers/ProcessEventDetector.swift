import Foundation
import Observation

/// Detects lifecycle events by diffing two consecutive snapshots of the
/// service list. Reusable by both the main window and the menu bar monitor.
enum ProcessEventDetector {

    struct DetectedEvent: Sendable {
        let serviceID: String
        let kind: ProcessEventKind
        let detail: String
    }

    static func detectEvents(between oldServices: [Service], and newServices: [Service]) -> [DetectedEvent] {
        guard !oldServices.isEmpty, !newServices.isEmpty else { return [] }

        let oldByID = Dictionary(uniqueKeysWithValues: oldServices.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: newServices.map { ($0.id, $0) })
        var detected: [DetectedEvent] = []

        for new in newServices {
            guard let old = oldByID[new.id] else {
                detected.append(DetectedEvent(serviceID: new.id, kind: .started, detail: "Service appeared"))
                continue
            }

            if old.status != new.status,
               let kind = transition(from: old.status, to: new.status) {
                detected.append(DetectedEvent(serviceID: new.id, kind: kind, detail: statusDetail(kind)))
            }

            if old.status == .running, new.status == .running,
               old.pid != 0, new.pid != 0, old.pid != new.pid {
                detected.append(DetectedEvent(serviceID: new.id, kind: .restarted, detail: "PID changed \(old.pid) → \(new.pid)"))
            } else if old.status == .running, new.status == .running,
                      let oldUptime = old.uptime, let newUptime = new.uptime,
                      oldUptime > newUptime + 5 {
                detected.append(DetectedEvent(serviceID: new.id, kind: .restarted, detail: "Uptime reset"))
            }
        }

        for old in oldServices where newByID[old.id] == nil {
            detected.append(DetectedEvent(serviceID: old.id, kind: .stopped, detail: "Service disappeared"))
        }

        return detected
    }

    private static func transition(from old: ServiceStatus, to new: ServiceStatus) -> ProcessEventKind? {
        switch (old, new) {
        case (.running, .stopped), (.starting, .stopped), (.stopping, .stopped):
            return .stopped
        case (.running, .exited), (.starting, .exited):
            return .exited
        case (.running, .fatal), (.starting, .fatal):
            return .fatal
        case (.running, .backingoff), (.starting, .backingoff):
            return .crashed
        case (.stopped, .running), (.exited, .running), (.fatal, .running), (.backingoff, .running):
            return .started
        case (.starting, .running), (.stopping, .running):
            return .running
        default:
            return nil
        }
    }

    private static func statusDetail(_ kind: ProcessEventKind) -> String {
        switch kind {
        case .started: "Process started"
        case .stopped: "Process stopped"
        case .exited: "Process exited"
        case .fatal: "Process entered FATAL state"
        case .crashed: "Process crashed (backing off)"
        case .running: "Process is running"
        default: ""
        }
    }
}
