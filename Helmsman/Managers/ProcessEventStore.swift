import Foundation
import Observation

@MainActor
@Observable
final class ProcessEventStore {
    private struct RunSegment {
        let start: Date
        var end: Date?
    }

    private var events: [String: [ProcessEvent]] = [:]
    private var openSegments: [String: RunSegment] = [:]
    private var closedSegments: [String: [RunSegment]] = [:]

    let maxEventsPerService = 500

    func record(_ kind: ProcessEventKind, detail: String, for serviceID: String) {
        var list = events[serviceID] ?? []
        var resolvedDetail = detail

        if kind == .restarted {
            let restartNumber = list.filter { $0.kind == .restarted }.count + 1
            resolvedDetail = resolvedDetail.isEmpty ? "Restart #\(restartNumber)" : "Restart #\(restartNumber) - \(resolvedDetail)"
        }

        list.append(ProcessEvent(timestamp: Date(), kind: kind, detail: resolvedDetail))
        if list.count > maxEventsPerService {
            list.removeFirst(list.count - maxEventsPerService)
        }
        events[serviceID] = list

        switch kind {
        case .started, .running, .restarted:
            if openSegments[serviceID] == nil {
                openSegments[serviceID] = RunSegment(start: Date())
            }
        case .stopped, .crashed, .exited, .fatal:
            if var segment = openSegments[serviceID] {
                segment.end = Date()
                closedSegments[serviceID, default: []].append(segment)
                openSegments[serviceID] = nil
            }
        default:
            break
        }
    }

    func events(for serviceID: String) -> [ProcessEvent] {
        events[serviceID] ?? []
    }

    func restartCount(for serviceID: String) -> Int {
        events[serviceID]?.filter { $0.kind == .restarted }.count ?? 0
    }

    func crashCount(for serviceID: String) -> Int {
        let kinds: [ProcessEventKind] = [.crashed, .exited, .fatal]
        return events[serviceID]?.filter { kinds.contains($0.kind) }.count ?? 0
    }

    func averageRuntime(for serviceID: String) -> TimeInterval? {
        let segments = closedSegments[serviceID] ?? []
        guard !segments.isEmpty else { return nil }
        let total = segments.reduce(0) { acc, segment in
            guard let end = segment.end else { return acc }
            return acc + end.timeIntervalSince(segment.start)
        }
        return total / Double(segments.count)
    }

    func clear(for serviceID: String) {
        events[serviceID] = nil
        closedSegments[serviceID] = nil
        openSegments[serviceID] = nil
    }

    func clearAll() {
        events.removeAll()
        closedSegments.removeAll()
        openSegments.removeAll()
    }
}
