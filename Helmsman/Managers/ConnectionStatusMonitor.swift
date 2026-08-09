import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class ConnectionStatusMonitor {
    struct Status: Identifiable {
        let id: UUID
        var name: String
        var isConnected: Bool
        var runningCount: Int
        var totalCount: Int
        var attentionCount: Int
        var lastUpdated: Date?
        var lastError: String?
    }

    private(set) var statuses: [UUID: Status] = [:]
    private var pollTask: Task<Void, Never>?
    private var managers: [UUID: ServiceManager] = [:]
    private var currentConnections: [Connection] = []
    private var restartWindows: [String: [Date]] = [:]
    private var notifiedServiceIDs: Set<String> = []
    private var notificationsAuthorized = false

    private let pollInterval: Duration = .seconds(10)
    private let restartThreshold = 3
    private let restartWindowInterval: TimeInterval = 300
    private let cooldownInterval: TimeInterval = 600

    var statusList: [Status] {
        statuses.values.sorted { $0.name < $1.name }
    }

    var totalAttention: Int {
        statuses.values.reduce(0) { $0 + $1.attentionCount }
    }

    var isHealthy: Bool {
        !statuses.isEmpty && statuses.allSatisfy { $0.value.isConnected && $0.value.attentionCount == 0 }
    }

    func start(connections: [Connection]) {
        currentConnections = connections

        let ids = Set(connections.map(\.id))
        managers = managers.filter { ids.contains($0.key) }
        for connection in connections where managers[connection.id] == nil {
            managers[connection.id] = ServiceManager(connection: connection)
        }

        requestNotificationAuthorization()

        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAll()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(10))
            }
        }
    }

    func refreshNow() async {
        await pollAll()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        managers.removeAll()
        statuses.removeAll()
        restartWindows.removeAll()
        notifiedServiceIDs.removeAll()
    }

    // MARK: - Polling

    private func pollAll() async {
        for connection in currentConnections {
            guard let manager = managers[connection.id] else { continue }
            let oldServices = manager.services
            await manager.refresh()
            let newServices = manager.services

            statuses[connection.id] = Status(
                id: connection.id,
                name: connection.name,
                isConnected: manager.isConnected,
                runningCount: newServices.filter { $0.status == .running }.count,
                totalCount: newServices.count,
                attentionCount: newServices.filter { $0.status.isAttention }.count,
                lastUpdated: Date(),
                lastError: manager.lastError?.localizedDescription
            )

            if manager.isConnected, !oldServices.isEmpty {
                let events = ProcessEventDetector.detectEvents(between: oldServices, and: newServices)
                let incidents = events.filter {
                    $0.kind == .restarted || $0.kind == .crashed || $0.kind == .fatal
                }
                if !incidents.isEmpty {
                    registerIncidents(incidents, services: newServices, connection: connection)
                }
            }
        }
    }

    // MARK: - Restart notifications

    private func registerIncidents(
        _ events: [ProcessEventDetector.DetectedEvent],
        services: [Service],
        connection: Connection
    ) {
        let now = Date()

        for event in events {
            restartWindows[event.serviceID, default: []].append(now)
            restartWindows[event.serviceID]?.removeAll { now.timeIntervalSince($0) > restartWindowInterval }

            let recent = restartWindows[event.serviceID] ?? []
            if recent.count >= restartThreshold, !notifiedServiceIDs.contains(event.serviceID) {
                notifiedServiceIDs.insert(event.serviceID)
                let name = services.first(where: { $0.id == event.serviceID })?.name ?? event.serviceID
                postNotification(
                    title: "Frequent Restarts",
                    body: "\(name) on \(connection.name) restarted \(recent.count) times in the last \(Int(restartWindowInterval / 60)) minutes."
                )
            }
        }

        for serviceID in notifiedServiceIDs {
            guard let window = restartWindows[serviceID], let last = window.last else { continue }
            if now.timeIntervalSince(last) > cooldownInterval {
                notifiedServiceIDs.remove(serviceID)
                restartWindows[serviceID] = []
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        guard !notificationsAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.notificationsAuthorized = granted
            }
        }
    }

    private func postNotification(title: String, body: String) {
        guard notificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension ServiceStatus {
    var isAttention: Bool {
        switch self {
        case .backingoff, .fatal, .unknown:
            return true
        default:
            return false
        }
    }
}
