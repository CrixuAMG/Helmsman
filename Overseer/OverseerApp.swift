import SwiftUI
import SwiftData

@main
struct OverseerApp: App {
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
        WindowGroup {
            ConnectionWindow()
                .frame(minWidth: 800, minHeight: 560)
        }
        .modelContainer(sharedModelContainer)

        WindowGroup(id: "main-window", for: UUID.self) { $connectionID in
            if let connectionID = connectionID {
                MainWindowWrapper(connectionID: connectionID)
                    .frame(minWidth: 700, minHeight: 500)
            }
        }
        .modelContainer(sharedModelContainer)
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
