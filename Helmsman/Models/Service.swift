import Foundation

struct Service: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let group: String
    var status: ServiceStatus
    var description: String
    var pid: Int
    var uptime: TimeInterval?
    var exitStatus: Int?
    var lastUpdated: Date

    var controlName: String {
        group == name ? name : "\(group):\(name)"
    }

    var displayName: String {
        name == "00" && group != name ? group : name
    }

    var displayGroup: String? {
        guard group != name, name != "00" else { return nil }
        return group
    }

    init(
        name: String,
        group: String,
        status: ServiceStatus,
        description: String,
        pid: Int,
        uptime: TimeInterval? = nil,
        exitStatus: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = "\(group):\(name)"
        self.name = name
        self.group = group
        self.status = status
        self.description = description
        self.pid = pid
        self.uptime = uptime
        self.exitStatus = exitStatus
        self.lastUpdated = lastUpdated
    }
}
