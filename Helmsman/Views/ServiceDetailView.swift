import SwiftUI

struct ServiceDetailView: View {
    let service: Service
    let metricsStore: ProcessMetricsStore
    let logStore: ProcessLogStore
    let eventStore: ProcessEventStore
    let memoryDisplayUnit: MemoryDisplayUnit
    let isPerformingAction: Bool
    let isFavorite: Bool
    let isProduction: Bool
    let onToggleFavorite: () -> Void
    let onToggleProduction: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onClearLogs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(24)
            Divider()
            TabView {
                ServiceOverviewView(
                    service: service,
                    metricsStore: metricsStore,
                    memoryDisplayUnit: memoryDisplayUnit
                )
                .padding(24)
                .tabItem {
                    Label("Overview", systemImage: "info.circle")
                }

                ServiceLogsView(
                    service: service,
                    logStore: logStore,
                    onClear: onClearLogs
                )
                .padding(24)
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }

                ServiceTimelineView(
                    service: service,
                    eventStore: eventStore,
                    metricsStore: metricsStore,
                    memoryDisplayUnit: memoryDisplayUnit
                )
                .padding(24)
                .tabItem {
                    Label("Timeline", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .background(.background)
        .id(service.id)
    }

    private var header: some View {
        HStack(spacing: 16) {
            StatusBadge(status: service.status)
                .scaleEffect(1.5)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                if let displayGroup = service.displayGroup {
                    Text(displayGroup)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 188, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    Button(action: onToggleFavorite) {
                        Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                    }
                    .help(isFavorite ? "Remove from favorites" : "Add to favorites")

                    Button(action: onToggleProduction) {
                        Label(
                            isProduction ? "Production" : "Mark Production",
                            systemImage: isProduction ? "shield.lefthalf.filled" : "shield"
                        )
                    }
                    .help(isProduction ? "Remove production mark" : "Mark as production service")
                    .tint(isProduction ? .orange : .accentColor)

                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(service.status == .running)

                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(service.status == .stopped)

                    Button(action: onRestart) {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
