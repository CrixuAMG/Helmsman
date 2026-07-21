import Foundation

@MainActor
@Observable
final class ProcessMetricsStore {
    private var history: [String: [ProcessMetrics]] = [:]

    let maxAge: TimeInterval = 1800
    let maxPoints = 900

    func add(_ metrics: ProcessMetrics, for serviceID: String) {
        add(contentsOf: [(serviceID: serviceID, metrics: metrics)])
    }

    func add(contentsOf collectedMetrics: [(serviceID: String, metrics: ProcessMetrics)]) {
        let cutoff = Date().addingTimeInterval(-maxAge)

        for item in collectedMetrics {
            history[item.serviceID, default: []].append(item.metrics)
            trimHistory(for: item.serviceID, cutoff: cutoff)
        }
    }

    private func trimHistory(for serviceID: String, cutoff: Date) {
        guard var points = history[serviceID] else { return }

        points.removeAll { $0.timestamp < cutoff }

        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }

        history[serviceID] = points
    }

    func getHistory(for serviceID: String) -> [ProcessMetrics] {
        history[serviceID] ?? []
    }

    func getLatest(for serviceID: String) -> ProcessMetrics? {
        history[serviceID]?.last
    }

    func clear(for serviceID: String) {
        history[serviceID] = nil
    }

    func clearAll() {
        history.removeAll()
    }
}
