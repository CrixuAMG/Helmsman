import SwiftUI

struct MainWindow: View {
    let connection: Connection
    @State private var viewModel: MainWindowViewModel

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
            await viewModel.refresh()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .alert(item: $viewModel.safeModeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Confirm")) {
                    Task { await alert.action() }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $viewModel.errorAlert) { alert in
            if let onReconnect = alert.onReconnect {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message + (alert.retryCount > 0 ? "\n\nRetry attempt \(alert.retryCount) of 3" : "")),
                    primaryButton: .default(Text("Retry")) {
                        Task { await alert.onRetry() }
                    },
                    secondaryButton: .default(Text("Reconnect")) {
                        Task { await onReconnect() }
                    }
                )
            } else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK")) {
                        Task { await alert.onRetry() }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let serviceID = viewModel.selectedServiceID,
           let service = viewModel.services.first(where: { $0.id == serviceID }) {
            ServiceDetailView(
                service: service,
                onStart: { viewModel.start(service) },
                onStop: { viewModel.stop(service) },
                onRestart: { viewModel.restart(service) }
            )

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
    }
}
