import Foundation
import Observation

@Observable
final class PollingEngine {
    var isPolling: Bool = false
    var lastPollTime: Date?
    var pollCount: Int = 0
    
    private var pollingTask: Task<Void, Never>?
    private var interval: TimeInterval
    private var refreshAction: (() async -> Void)?
    
    init(interval: TimeInterval = 5.0) {
        self.interval = interval
    }
    
    deinit {
        stop()
    }
    
    func start(interval: TimeInterval, refreshAction: @escaping () async -> Void) {
        stop()
        
        self.interval = interval
        self.refreshAction = refreshAction
        self.isPolling = true
        
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                await self.refreshAction?()
                await MainActor.run {
                    self.lastPollTime = Date()
                    self.pollCount += 1
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
            }
            
            await MainActor.run {
                self?.isPolling = false
            }
        }
    }
    
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
    
    func updateInterval(_ newInterval: TimeInterval) {
        guard let refreshAction = refreshAction else { return }
        start(interval: newInterval, refreshAction: refreshAction)
    }
    
    func pollNow() async {
        await refreshAction?()
        await MainActor.run {
            lastPollTime = Date()
            pollCount += 1
        }
    }
}
