import SwiftUI
import SwiftData

struct ConnectionWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Connection.name) private var connections: [Connection]
    @State private var viewModel = ConnectionWindowViewModel()
    @Bindable private var monitor: ConnectionStatusMonitor

    init(monitor: ConnectionStatusMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        HSplitView {
            connectionList
                .frame(minWidth: 280, idealWidth: 320)

            detailPane
                .frame(minWidth: 480)
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            viewModel.setConnectionManager(ConnectionManager(modelContext: modelContext))
            viewModel.loadConnections(connections)
        }
        .onChange(of: connections) { _, newConnections in
            viewModel.loadConnections(newConnections)
        }
        .task {
            monitor.start(connections: connections)
        }
    }

    private var connectionList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedConnectionID },
                set: { id in
                    viewModel.selectConnection(connections.first { $0.id == id })
                }
            )) {
                ForEach(connections) { connection in
                    ConnectionRowView(connection: connection)
                        .tag(connection.id)
                        .contextMenu {
                            Button("Duplicate") {
                                viewModel.duplicate(connection)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                viewModel.delete(connection)
                            }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button(action: { viewModel.newConnection() }) {
                    Label("New Connection", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private var detailPane: some View {
        Group {
            if viewModel.isEditing {
                ConnectionFormView(viewModel: viewModel)
            } else if let id = viewModel.selectedConnectionID,
                      let connection = connections.first(where: { $0.id == id }) {
                connectionDetail(connection)
            } else {
                emptyState
            }
        }
    }

    private func connectionDetail(_ connection: Connection) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(connection.accentColor)
                    .frame(width: 6, height: 48)

                Text(connection.name)
                    .font(.title)
                    .fontWeight(.semibold)

                Text("\(connection.username)@\(connection.host):\(connection.port)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Method:")
                        .foregroundStyle(.secondary)
                    Text(connection.connectionMethod.displayName)
                }
                HStack {
                    Text("Authentication:")
                        .foregroundStyle(.secondary)
                    Text(connection.authenticationMethod.displayName)
                }
            if connection.safeMode {
                Label("Safe Mode Enabled", systemImage: "shield.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            }
            .font(.body)

            diskUsageSection(connection)

            HStack(spacing: 12) {
                Button("Edit") {
                    viewModel.editConnection(connection)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: .command)

                Button("Connect") {
                    openWindow(id: "main-window", value: connection.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder
    private func diskUsageSection(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Log Disk Usage", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refreshDiskUsage(for: connection)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                if connection.connectionMethod == .local {
                    Button("Cleanup Now") {
                        viewModel.cleanupOldLogs(for: connection)
                    }
                    .buttonStyle(.bordered)
                    .help("Delete resolved log files older than the retention period")
                }
            }

            if connection.connectionMethod != .local {
                Text("Disk usage insight and log cleanup are only available for local connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.logDiskUsage.isEmpty {
                Text("No log files resolved. Set a supervisor config path to track log sizes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Total: \(viewModel.totalLogBytes.formatted(.byteCount(style: .file)))")
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Retention: \(connection.logRetentionDays) days\(connection.autoClearOldLogs ? " · auto-clean on" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(viewModel.logDiskUsage) { usage in
                            HStack {
                                Text(usage.serviceName)
                                Spacer()
                                Text(usage.totalBytes.formatted(.byteCount(style: .file)))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 140)

                if let result = viewModel.lastCleanupResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .onAppear {
            viewModel.refreshDiskUsage(for: connection)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Connection Selected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Select a connection from the list or create a new one.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
