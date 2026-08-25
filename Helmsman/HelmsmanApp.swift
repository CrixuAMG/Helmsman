import SwiftUI
import SwiftData

@main
struct HelmsmanApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var showOnboarding = false
    @State private var statusMonitor = ConnectionStatusMonitor()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Connection.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("Connections", id: "connections") {
            ConnectionWindow(monitor: statusMonitor)
                .frame(minWidth: 800, minHeight: 560)
                .preferredColorScheme(settings.theme.colorScheme)
                .overlay {
                    if showOnboarding {
                        OnboardingWindow(settings: settings) {
                            showOnboarding = false
                        }
                    }
                }
                .onAppear {
                    if !settings.hasCompletedOnboarding {
                        showOnboarding = true
                    }
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsWindow()
        }

        WindowGroup(id: "main-window", for: UUID.self) { $connectionID in
            if let connectionID = connectionID {
                    MainWindowWrapper(connectionID: connectionID)
                    .frame(minWidth: 800, minHeight: 500)
                    .preferredColorScheme(settings.theme.colorScheme)
            }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            HelmsmanCommands()
        }

        MenuBarExtra {
            MenuBarView(monitor: statusMonitor)
        } label: {
            Label {
                Text("Helmsman")
            } icon: {
                Image(systemName: statusMonitor.isHealthy
                      ? "checkmark.seal"
                      : (statusMonitor.totalAttention > 0 ? "exclamationmark.triangle" : "xmark.seal"))
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

struct HelmsmanCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Show Connections") {
                openWindow(id: "connections")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}

struct MainWindowWrapper: View {
    let connectionID: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var connections: [Connection]

    init(connectionID: UUID) {
        self.connectionID = connectionID
        _connections = Query(filter: #Predicate<Connection> { $0.id == connectionID })
    }

    var body: some View {
        if let connection = connections.first {
            MainWindow(connection: connection)
        } else {
            Text("Connection not found")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
