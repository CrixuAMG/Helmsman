import Foundation

@Observable
final class ProcessMetricsPoller {
    var isPolling = false

    private var task: Task<Void, Never>?
    private let interval: TimeInterval = 2.0

    func start(
        serviceManager: ServiceManager,
        store: ProcessMetricsStore,
        servicesProvider: @escaping () async -> [Service]
    ) {
        stop()
        isPolling = true
        print("[DEBUG] ProcessMetricsPoller.start() - starting metrics collection")

        task = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let runningServices = await servicesProvider().filter { $0.status == .running && $0.pid > 0 }
                print("[DEBUG] ProcessMetricsPoller: found \(runningServices.count) running services with PIDs")

                await withTaskGroup(of: (String, ProcessMetrics)?.self) { group in
                    for service in runningServices {
                        group.addTask {
                            do {
                                let metrics = try await serviceManager.getProcessMetrics(pid: service.pid)
                                print("[DEBUG] ProcessMetricsPoller: collected metrics for \(service.name) (pid: \(service.pid)) - CPU: \(String(format: "%.1f", metrics.cpuPercent))%, Memory: \(String(format: "%.1f", metrics.memoryMB)) MB")
                                return (service.id, metrics)
                            } catch {
                                print("[DEBUG] ProcessMetricsPoller: FAILED to collect metrics for \(service.name) (pid: \(service.pid)): \(error.localizedDescription)")
                                return nil
                            }
                        }
                    }

                    var collectedMetrics: [(serviceID: String, metrics: ProcessMetrics)] = []
                    collectedMetrics.reserveCapacity(runningServices.count)

                    for await result in group {
                        if let result {
                            collectedMetrics.append((serviceID: result.0, metrics: result.1))
                        }
                    }

                    if !collectedMetrics.isEmpty {
                        print("[DEBUG] ProcessMetricsPoller: adding \(collectedMetrics.count) metrics to store")
                        store.add(contentsOf: collectedMetrics)
                    }
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                } catch {
                    break
                }
            }

            await MainActor.run { self.isPolling = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPolling = false
    }

    deinit {
        task?.cancel()
    }
}
