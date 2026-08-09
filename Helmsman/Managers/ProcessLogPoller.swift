import Foundation
import Observation

@Observable
final class ProcessLogPoller {
    var isPolling = false
    var lastPollDate: Date?

    private var task: Task<Void, Never>?
    private let interval: TimeInterval = 2.0

    func start(service: Service, serviceManager: ServiceManager, store: ProcessLogStore) {
        stop()

        let serviceID = service.id
        let controlName = service.controlName
        let maxBytes = store.maxFetchBytes
        isPolling = true

        task = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                for stream in [LogStream.stdout, .stderr] {
                    let offset = store.offset(for: serviceID, stream: stream)
                    do {
                        let chunk = try await serviceManager.readProcessLog(
                            controlName: controlName,
                            stderr: stream == .stderr,
                            offset: offset,
                            maxBytes: maxBytes
                        )
                        await MainActor.run {
                            store.merge(chunk, for: serviceID, stream: stream)
                        }
                    } catch {
                        await MainActor.run {
                            store.record(error: error, for: serviceID, stream: stream)
                        }
                    }
                }

                await MainActor.run { self.lastPollDate = Date() }

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
