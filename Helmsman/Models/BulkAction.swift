import Foundation

enum BulkServiceAction: String, Sendable {
    case start
    case stop
    case restart

    var displayName: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .restart: "Restart"
        }
    }

    var verb: String {
        switch self {
        case .start: "start"
        case .stop: "stop"
        case .restart: "restart"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        }
    }
}

enum BulkPreset: String, CaseIterable, Identifiable, Sendable {
    case startAll
    case stopAll
    case restartAll
    case restartQueueWorkers
    case stopCronJobs
    case restartExceptDatabases
    case startAPIServices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startAll: "Start all services"
        case .stopAll: "Stop all services"
        case .restartAll: "Restart all services"
        case .restartQueueWorkers: "Restart queue workers"
        case .stopCronJobs: "Stop cron jobs"
        case .restartExceptDatabases: "Restart everything except databases"
        case .startAPIServices: "Start API stack"
        }
    }

    var action: BulkServiceAction {
        switch self {
        case .startAll, .startAPIServices: .start
        case .stopAll, .stopCronJobs: .stop
        case .restartAll, .restartQueueWorkers, .restartExceptDatabases: .restart
        }
    }

    var systemImage: String {
        action.systemImage
    }

    func matchingServices(in services: [Service]) -> [Service] {
        switch self {
        case .startAll:
            return services.filter { $0.status != .running }
        case .stopAll:
            return services.filter { $0.status == .running }
        case .restartAll:
            return services.filter { $0.status == .running }
        case .restartQueueWorkers:
            return services.filter { service in
                service.status == .running && Self.containsAny(service, keywords: Self.queueKeywords)
            }
        case .stopCronJobs:
            return services.filter { service in
                service.status == .running && Self.containsAny(service, keywords: Self.cronKeywords)
            }
        case .restartExceptDatabases:
            return services.filter { service in
                service.status == .running && !Self.containsAny(service, keywords: Self.databaseKeywords)
            }
        case .startAPIServices:
            return services.filter { service in
                service.status != .running && Self.containsAny(service, keywords: Self.apiKeywords)
            }
        }
    }

    private static let queueKeywords = ["queue", "worker"]
    private static let cronKeywords = ["cron", "scheduler", "scheduled"]
    private static let databaseKeywords = ["db", "database", "mysql", "mariadb", "postgres", "sql", "redis"]
    private static let apiKeywords = ["api", "web", "http", "server", "nginx"]

    private static func containsAny(_ service: Service, keywords: [String]) -> Bool {
        let haystack = "\(service.name) \(service.group)".lowercased()
        return keywords.contains { haystack.contains($0) }
    }
}
