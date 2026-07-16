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

    var safeModeAlert: SafeModeAlert?

    private let connection: Connection
    private let serviceManager: ServiceManager

    init(connection: Connection) {
        self.connection = connection
        self.serviceManager = ServiceManager(connection: connection)
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
        isLoading = false
    }

    func start(_ service: Service) {
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
        do {
            try await serviceManager.start(service)
            await refresh()
        } catch {
            lastError = error
        }
    }

    private func performStop(_ service: Service) async {
        do {
            try await serviceManager.stop(service)
            await refresh()
        } catch {
            lastError = error
        }
    }

    private func performRestart(_ service: Service) async {
        do {
            try await serviceManager.restart(service)
            await refresh()
        } catch {
            lastError = error
        }
    }
}

struct SafeModeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: () async -> Void
}
