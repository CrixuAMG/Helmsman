import Foundation
import Observation

@Observable
final class MainWindowViewModel {
    var services: [Service] = []
    var selectedServiceID: String?
    var isLoading: Bool = false
    var isConnected: Bool = false
    var activeProviderName: String?
    var lastError: Error?
    var searchText: String = ""
    var retryCount: Int = 0
    private(set) var activeActionServiceIDs: Set<String> = []

    var safeModeAlert: SafeModeAlert?
    var errorAlert: ErrorAlert?

    private let connection: Connection
    private let serviceManager: ServiceManager
    let pollingEngine: PollingEngine
    let metricsStore = ProcessMetricsStore()
    let metricsPoller = ProcessMetricsPoller()

    init(connection: Connection) {
        self.connection = connection
        self.serviceManager = ServiceManager(connection: connection)
        self.pollingEngine = PollingEngine(interval: connection.pollingInterval)
    }

    var filteredServices: [Service] {
        if searchText.isEmpty {
            return services
        }
        return services.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.group.localizedCaseInsensitiveContains(searchText)
        }
    }

    func refresh() async {
        isLoading = true
        await serviceManager.refresh()
        services = serviceManager.services
        isConnected = serviceManager.isConnected
        activeProviderName = serviceManager.activeProviderName
        lastError = serviceManager.lastError
        retryCount = serviceManager.retryCount
        isLoading = false

        if let error = lastError {
            errorAlert = ErrorAlert(
                title: "Connection Error",
                message: error.localizedDescription,
                retryCount: retryCount,
                onRetry: { [weak self] in
                    await self?.refresh()
                },
                onReconnect: { [weak self] in
                    await self?.reconnect()
                }
            )
        }
    }

    func reconnect() async {
        isLoading = true
        await serviceManager.reconnect()
        services = serviceManager.services
        isConnected = serviceManager.isConnected
        activeProviderName = serviceManager.activeProviderName
        lastError = serviceManager.lastError
        retryCount = serviceManager.retryCount
        isLoading = false
        errorAlert = nil
    }

    func startPolling() {
        pollingEngine.start(interval: connection.pollingInterval) { [weak self] in
            await self?.refresh()
        }
        metricsPoller.start(serviceManager: serviceManager, store: metricsStore) { [weak self] in
            await MainActor.run { self?.services ?? [] }
        }
    }

    func stopPolling() {
        pollingEngine.stop()
        metricsPoller.stop()
    }

    func isPerformingAction(for service: Service) -> Bool {
        activeActionServiceIDs.contains(service.id)
    }

    func start(_ service: Service) {
        guard !isPerformingAction(for: service) else { return }

        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Start Service",
                message: "Are you sure you want to start '\(service.name)'?",
                action: { [weak self] in
                    await self?.performStart(service)
                }
            )
        } else {
            Task { await performStart(service) }
        }
    }

    func stop(_ service: Service) {
        guard !isPerformingAction(for: service) else { return }

        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Stop Service",
                message: "Are you sure you want to stop '\(service.name)'?",
                action: { [weak self] in
                    await self?.performStop(service)
                }
            )
        } else {
            Task { await performStop(service) }
        }
    }

    func restart(_ service: Service) {
        guard !isPerformingAction(for: service) else { return }

        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Restart Service",
                message: "Are you sure you want to restart '\(service.name)'?",
                action: { [weak self] in
                    await self?.performRestart(service)
                }
            )
        } else {
            Task { await performRestart(service) }
        }
    }

    private func performStart(_ service: Service) async {
        activeActionServiceIDs.insert(service.id)
        defer { activeActionServiceIDs.remove(service.id) }

        do {
            try await serviceManager.start(service)
            await refresh()
        } catch {
            errorAlert = ErrorAlert(
                title: "Action Failed",
                message: "Failed to start '\(service.name)': \(error.localizedDescription)",
                retryCount: 0,
                onRetry: { [weak self] in
                    await self?.performStart(service)
                },
                onReconnect: nil
            )
        }
    }

    private func performStop(_ service: Service) async {
        activeActionServiceIDs.insert(service.id)
        defer { activeActionServiceIDs.remove(service.id) }

        do {
            try await serviceManager.stop(service)
            await refresh()
        } catch {
            errorAlert = ErrorAlert(
                title: "Action Failed",
                message: "Failed to stop '\(service.name)': \(error.localizedDescription)",
                retryCount: 0,
                onRetry: { [weak self] in
                    await self?.performStop(service)
                },
                onReconnect: nil
            )
        }
    }

    private func performRestart(_ service: Service) async {
        activeActionServiceIDs.insert(service.id)
        defer { activeActionServiceIDs.remove(service.id) }

        do {
            try await serviceManager.restart(service)
            await refresh()
        } catch {
            errorAlert = ErrorAlert(
                title: "Action Failed",
                message: "Failed to restart '\(service.name)': \(error.localizedDescription)",
                retryCount: 0,
                onRetry: { [weak self] in
                    await self?.performRestart(service)
                },
                onReconnect: nil
            )
        }
    }
}

struct SafeModeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: () async -> Void
}

struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retryCount: Int
    let onRetry: () async -> Void
    let onReconnect: (() async -> Void)?
}
