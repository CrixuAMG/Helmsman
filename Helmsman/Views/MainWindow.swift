import SwiftUI
import SwiftData

struct MainWindow: View {
    let connection: Connection
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MainWindowViewModel
    @State private var activeAlert: ActiveAlert?
    @State private var showGraphSheet = false

    enum ActiveAlert: Identifiable {
        case safeMode(SafeModeAlert)
        case error(ErrorAlert)

        var id: UUID {
            switch self {
            case .safeMode(let alert): return alert.id
            case .error(let alert): return alert.id
            }
        }
    }

    init(connection: Connection) {
        self.connection = connection
        _viewModel = State(initialValue: MainWindowViewModel(connection: connection))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            ServiceListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            detailPane
        }
        .navigationTitle(connection.name)
        .toolbar {
            toolbarContent
        }

        .task {
            viewModel.onConnectionDidChange = {
                try? modelContext.save()
            }
            await viewModel.refresh()
            viewModel.startPolling()
            viewModel.startLogPolling(for: viewModel.selectedServiceID)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onChange(of: viewModel.selectedServiceID) { _, newValue in
            viewModel.startLogPolling(for: newValue)
        }
        .onChange(of: viewModel.safeModeAlert?.id) { _, newID in
            if let alert = viewModel.safeModeAlert, newID != nil {
                activeAlert = .safeMode(alert)
            } else if case .safeMode = activeAlert {
                activeAlert = nil
            }
        }
        .onChange(of: viewModel.errorAlert?.id) { _, newID in
            if let alert = viewModel.errorAlert, newID != nil {
                activeAlert = .error(alert)
            } else if case .error = activeAlert {
                activeAlert = nil
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .safeMode(let safeModeAlert):
                return Alert(
                    title: Text(safeModeAlert.title),
                    message: Text(safeModeAlert.message),
                    primaryButton: .destructive(Text("Confirm")) {
                        viewModel.safeModeAlert = nil
                        Task { await safeModeAlert.action() }
                    },
                    secondaryButton: .cancel {
                        viewModel.safeModeAlert = nil
                    }
                )
            case .error(let errorAlert):
                if let onReconnect = errorAlert.onReconnect {
                    return Alert(
                        title: Text(errorAlert.title),
                        message: Text(errorAlert.message + (errorAlert.retryCount > 0 ? "\n\nRetry attempt \(errorAlert.retryCount) of 3" : "")),
                        primaryButton: .default(Text("Retry")) {
                            viewModel.errorAlert = nil
                            Task { await errorAlert.onRetry() }
                        },
                        secondaryButton: .default(Text("Reconnect")) {
                            viewModel.errorAlert = nil
                            Task { await onReconnect() }
                        }
                    )
                } else {
                    return Alert(
                        title: Text(errorAlert.title),
                        message: Text(errorAlert.message),
                        dismissButton: .default(Text("OK")) {
                            viewModel.errorAlert = nil
                            Task { await errorAlert.onRetry() }
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showGraphSheet) {
            DependencyGraphSheetView(
                viewModel: viewModel,
                connection: connection
            )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if viewModel.selectedServiceIDs.count == 1,
           let serviceID = viewModel.selectedServiceID,
           let service = viewModel.services.first(where: { $0.id == serviceID }) {
            ServiceDetailView(
                service: service,
                metricsStore: viewModel.metricsStore,
                logStore: viewModel.logStore,
                eventStore: viewModel.eventStore,
                memoryDisplayUnit: AppSettings.shared.memoryDisplayUnit,
                isPerformingAction: viewModel.isPerformingAction(for: service),
                isFavorite: viewModel.isFavorite(service.id),
                isProduction: viewModel.isProduction(service.id),
                onToggleFavorite: { viewModel.toggleFavorite(for: service.id) },
                onToggleProduction: { viewModel.toggleProduction(for: service.id) },
                onStart: { viewModel.start(service) },
                onStop: { viewModel.stop(service) },
                onRestart: { viewModel.restart(service) },
                onClearLogs: {
                    Task { await viewModel.clearLogs(for: service) }
                }
            )

        } else if viewModel.selectedServices.count > 1 {
            bulkSelectionPane

        } else {
            VStack(spacing: 16) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)


                Text("No Service Selected")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Select a service from the list to view details.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
    }

    private var bulkSelectionPane: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("\(viewModel.selectedServices.count) Services Selected")
                .font(.title2)
                .fontWeight(.medium)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.selectedServices.sorted { $0.name < $1.name }) { service in
                        HStack(spacing: 8) {
                            StatusBadge(status: service.status)
                            Text(service.name)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                Button(action: viewModel.bulkStart) {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(viewModel.selectedServices.allSatisfy { $0.status == .running })

                Button(action: viewModel.bulkStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(viewModel.selectedServices.allSatisfy { $0.status == .stopped })

                Button(action: viewModel.bulkRestart) {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningServiceCount: Int {
        viewModel.services.filter { $0.status == .running }.count
    }

    private var attentionServiceCount: Int {
        viewModel.services.filter { service in
            switch service.status {
            case .backingoff, .fatal, .unknown:
                return true
            default:
                return false
            }
        }.count
    }

    private var sidebar: some View {
        List {
            Section("Connection") {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(connection.accentColor)
                        .frame(width: 4, height: 20)
                    
                    Label(connection.name, systemImage: "server.rack")
                        .foregroundStyle(.primary)
                }

                if let provider = viewModel.activeProviderName {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(provider)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }

            Section("Status") {
                HStack {
                    Text("Connected")
                    Spacer()
                    Circle()
                        .fill(viewModel.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                        .shadow(color: viewModel.isConnected ? .green.opacity(0.5) : .red.opacity(0.5), radius: 4)
                }

                HStack {
                    Text("Services")
                    Spacer()
                    Text("\(viewModel.services.count)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Running")
                    Spacer()
                    Text("\(runningServiceCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.green)
                }

                HStack {
                    Text("Attention")
                    Spacer()
                    Text("\(attentionServiceCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(attentionServiceCount > 0 ? .orange : .secondary)
                }

                if viewModel.pollingEngine.isPolling {
                    HStack {
                        Text("Auto-refresh")
                        Spacer()
                        Text("\(Int(connection.pollingInterval))s")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { Task { await viewModel.refresh() } }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel.isLoading)
        }

        ToolbarItem(placement: .primaryAction) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showGraphSheet = true
            } label: {
                Label("Dependency Graph", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .disabled(viewModel.services.isEmpty)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(BulkPreset.allCases) { preset in
                    Button {
                        viewModel.performPreset(preset)
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                    }
                }

                Divider()

                Button("Clear Selection") {
                    viewModel.selectedServiceIDs = []
                }
                .disabled(viewModel.selectedServiceIDs.isEmpty)
            } label: {
                Label("Bulk Actions", systemImage: "square.stack.3d.up")
            }
            .disabled(viewModel.services.isEmpty)
        }
    }
}
