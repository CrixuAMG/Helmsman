import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Bindable var monitor: ConnectionStatusMonitor
    @Environment(\.openWindow) private var openWindow
    @Query private var connections: [Connection]

    var body: some View {
        menuContent
            .task {
                monitor.start(connections: connections)
            }
            .onChange(of: connections.map(\.id)) { _, _ in
                monitor.start(connections: connections)
            }
    }

    @ViewBuilder
    private var menuContent: some View {
        if connections.isEmpty {
            Text("No connections configured")
                .padding(.vertical, 4)
            Divider()
            Button("Show Connections") {
                openWindow(id: "connections")
            }
        } else {
            ForEach(monitor.statusList) { status in
                Button {
                    openWindow(id: "main-window", value: status.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)

                        Text(status.name)
                            .lineLimit(1)

                        Spacer()

                        if status.isConnected {
                            Text("\(status.runningCount)/\(status.totalCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text("offline")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 240)
                }
            }

            if !monitor.statusList.isEmpty {
                Divider()
            }

            Button("Show Connections") {
                openWindow(id: "connections")
            }

            Button("Refresh Status") {
                Task { await monitor.refreshNow() }
            }

            Divider()

            Button("Quit Helmsman") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func statusColor(_ status: ConnectionStatusMonitor.Status) -> Color {
        if !status.isConnected {
            return .red
        }
        return status.attentionCount > 0 ? .orange : .green
    }
}
