import SwiftUI
import SwiftData

struct MainWindow: View {
    let connection: Connection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: MainWindowViewModel
    @State private var activeAlert: ActiveAlert?
    @State private var showGraphSheet = false
    @State private var showTagsSheet = false

    enum ActiveAlert: Identifiable {
        case safeMode(SafeModeAlert)

        var id: UUID {
            switch self {
            case .safeMode(let alert): return alert.id
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
                .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        }
        .navigationSplitViewStyle(.balanced)
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
            }
        }
        .alert(
            Text(viewModel.errorAlert?.title ?? "Connection Error"),
            isPresented: Binding(
                get: { viewModel.errorAlert != nil },
                set: { if !$0 { viewModel.errorAlert = nil } }
            ),
            presenting: viewModel.errorAlert
        ) { alert in
            if let onReconnect = alert.onReconnect {
                Button("Retry") {
                    viewModel.errorAlert = nil
                    Task { await alert.onRetry() }
                }
                Button("Reconnect") {
                    viewModel.errorAlert = nil
                    Task { await onReconnect() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.errorAlert = nil
                    openWindow(id: "connections")
                }
            } else {
                Button("OK") {
                    viewModel.errorAlert = nil
                    Task { await alert.onRetry() }
                }
            }
        } message: { alert in
            Text(alert.message + (alert.retryCount > 0 ? "\n\nRetry attempt \(alert.retryCount) of 3" : ""))
        }
        .sheet(isPresented: $showGraphSheet) {
            DependencyGraphSheetView(
                viewModel: viewModel,
                connection: connection
            )
        }
        .sheet(isPresented: $showTagsSheet) {
            ProcessTagsSheetView(viewModel: viewModel)
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
                onToggleFavorite: { viewModel.toggleFavorite(for: service.id) },
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
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
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

            if !viewModel.tagNames.isEmpty {
                Section("Tags") {
                    ForEach(viewModel.tagNames, id: \.self) { tag in
                        let taggedServices = viewModel.services(for: tag)
                        Button {
                            viewModel.toggleTagFilter(tag)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(connection.accentColor)
                                Text(tag)
                                Spacer()
                                Text("\(taggedServices.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if viewModel.activeTag == tag {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(connection.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(taggedServices.isEmpty)
                        .help("Select services tagged \(tag)")
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
                if viewModel.tagNames.isEmpty {
                    Text("No process tags configured")
                } else {
                    ForEach(viewModel.tagNames, id: \.self) { tag in
                        Menu {
                            Button {
                                viewModel.performTag(tag, action: .start)
                            } label: {
                                Label("Start", systemImage: BulkServiceAction.start.systemImage)
                            }
                            Button {
                                viewModel.performTag(tag, action: .stop)
                            } label: {
                                Label("Stop", systemImage: BulkServiceAction.stop.systemImage)
                            }
                            Button {
                                viewModel.performTag(tag, action: .restart)
                            } label: {
                                Label("Restart", systemImage: BulkServiceAction.restart.systemImage)
                            }
                        } label: {
                            Label(tag, systemImage: "tag.fill")
                        }
                    }
                }

                Divider()

                Button {
                    showTagsSheet = true
                } label: {
                    Label("Manage Process Tags...", systemImage: "tag")
                }
            } label: {
                Label("Bulk Actions", systemImage: "square.stack.3d.up")
            }
            .disabled(viewModel.services.isEmpty)
        }
    }
}
