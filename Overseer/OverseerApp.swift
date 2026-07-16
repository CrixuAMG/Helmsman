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
    }
}
