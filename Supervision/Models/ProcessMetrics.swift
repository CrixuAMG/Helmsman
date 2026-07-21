import Foundation

struct ProcessMetrics: Sendable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let cpuPercent: Double
    let memoryMB: Double
}
