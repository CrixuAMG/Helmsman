import Foundation

struct SupervisorProcess: Sendable {
    let name: String
    let group: String
    let status: ServiceStatus
    let description: String
    let pid: Int
    let uptime: TimeInterval?
    let exitStatus: Int?
}
