import Foundation

struct Service: Identifiable, Sendable {
    let id: String
    let name: String
    let group: String
    var status: ServiceStatus
    var description: String
    var pid: Int
    var uptime: TimeInterval?
    var exitStatus: Int?
    var lastUpdated: Date

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
