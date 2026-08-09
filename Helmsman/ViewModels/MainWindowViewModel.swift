import Foundation
import Observation

@Observable
final class MainWindowViewModel {
    var services: [Service] = []
    var selectedServiceIDs: Set<String> = []
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
    let logStore = ProcessLogStore()
    let logPoller = ProcessLogPoller()
    let eventStore = ProcessEventStore()
    private var hasLoadedOnce = false

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

    var selectedServiceID: String? {
        selectedServiceIDs.count == 1 ? selectedServiceIDs.first : nil
    }

    var selectedServices: [Service] {
        services.filter { selectedServiceIDs.contains($0.id) }
    }

    var isBulkActionActive: Bool {
        let selected = selectedServices
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy { activeActionServiceIDs.contains($0.id) }
    }

    func refresh() async {
        let oldServices = services
        isLoading = true
        await serviceManager.refresh()
        let newServices = serviceManager.services
        services = newServices
        isConnected = serviceManager.isConnected
        activeProviderName = serviceManager.activeProviderName
        lastError = serviceManager.lastError
        retryCount = serviceManager.retryCount
        isLoading = false

        if hasLoadedOnce {
            detectEvents(between: oldServices, and: newServices)
        } else if !newServices.isEmpty {
            hasLoadedOnce = true
        }

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
        logPoller.stop()
    }

    func startLogPolling(for serviceID: String?) {
        guard let serviceID else {
            logPoller.stop()
            return
        }
        guard let service = services.first(where: { $0.id == serviceID }) else {
            logPoller.stop()
            return
        }
        logPoller.start(service: service, serviceManager: serviceManager, store: logStore)
    }

    func clearLogs(for service: Service) async {
        do {
            try await serviceManager.clearProcessLogs(controlName: service.controlName)
            logStore.clear(for: service.id)
        } catch {
            errorAlert = ErrorAlert(
                title: "Action Failed",
                message: "Failed to clear logs for '\(service.name)': \(error.localizedDescription)",
                retryCount: 0,
                onRetry: { [weak self] in
                    await self?.clearLogs(for: service)
                },
                onReconnect: nil
            )
        }
    }

    func isPerformingAction(for service: Service) -> Bool {
        activeActionServiceIDs.contains(service.id)
    }

    private func detectEvents(between oldServices: [Service], and newServices: [Service]) {
        let detected = ProcessEventDetector.detectEvents(between: oldServices, and: newServices)
        guard !detected.isEmpty else { return }
        for event in detected {
            eventStore.record(event.kind, detail: event.detail, for: event.serviceID)
        }
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

    // MARK: - Bulk Actions

    func bulkStart() {
        guard !selectedServices.isEmpty else { return }
        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Start \(selectedServices.count) Services",
                message: bulkConfirmationMessage(action: "start"),
                action: { [weak self] in
                    await self?.performBulk(.start, services: self?.selectedServices ?? [])
                }
            )
        } else {
            Task { await performBulk(.start, services: selectedServices) }
        }
    }

    func bulkStop() {
        guard !selectedServices.isEmpty else { return }
        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Stop \(selectedServices.count) Services",
                message: bulkConfirmationMessage(action: "stop"),
                action: { [weak self] in
                    await self?.performBulk(.stop, services: self?.selectedServices ?? [])
                }
            )
        } else {
            Task { await performBulk(.stop, services: selectedServices) }
        }
    }

    func bulkRestart() {
        guard !selectedServices.isEmpty else { return }
        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "Restart \(selectedServices.count) Services",
                message: bulkConfirmationMessage(action: "restart"),
                action: { [weak self] in
                    await self?.performBulk(.restart, services: self?.selectedServices ?? [])
                }
            )
        } else {
            Task { await performBulk(.restart, services: selectedServices) }
        }
    }

    func performPreset(_ preset: BulkPreset) {
        let services = preset.matchingServices(in: services)
        guard !services.isEmpty else { return }

        if connection.safeMode {
            safeModeAlert = SafeModeAlert(
                title: "\(preset.action.displayName.uppercased()): \(preset.title)",
                message: "This will \(preset.action.verb) \(services.count) service(s):\n\n\(services.map(\.name).joined(separator: "\n"))",
                action: { [weak self] in
                    await self?.performBulk(preset.action, services: services)
                }
            )
        } else {
            Task { await performBulk(preset.action, services: services) }
        }
    }

    private func bulkConfirmationMessage(action: String) -> String {
        let names = selectedServices.prefix(12).map(\.name)
        let suffix = selectedServices.count > 12 ? "\n…and \(selectedServices.count - 12) more" : ""
        return "This will \(action) \(selectedServices.count) service(s):\n\n\(names.joined(separator: "\n"))\(suffix)"
    }

    private func performBulk(_ action: BulkServiceAction, services: [Service]) async {
        guard !services.isEmpty else { return }

        let ids = services.map(\.id)
        for id in ids { activeActionServiceIDs.insert(id) }
        defer { for id in ids { activeActionServiceIDs.remove(id) } }

        var failures: [String: String] = [:]

        for service in services {
            do {
                switch action {
                case .start: try await serviceManager.start(service)
                case .stop: try await serviceManager.stop(service)
                case .restart: try await serviceManager.restart(service)
                }
            } catch {
                failures[service.name] = error.localizedDescription
            }
        }

        await refresh()

        if !failures.isEmpty {
            let details = failures.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            errorAlert = ErrorAlert(
                title: "Some Actions Failed",
                message: "\(failures.count) of \(services.count) actions failed:\n\n\(details)",
                retryCount: 0,
                onRetry: { [weak self] in
                    let failedServices = services.filter { failures[$0.name] != nil }
                    await self?.performBulk(action, services: failedServices)
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
