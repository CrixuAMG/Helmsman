import Foundation

protocol ServiceProcess: Sendable {
    var name: String { get }
    var group: String { get }
    var status: ServiceStatus { get }
    var description: String { get }
    var pid: Int { get }
    var uptime: TimeInterval? { get }
    var exitStatus: Int? { get }
}
