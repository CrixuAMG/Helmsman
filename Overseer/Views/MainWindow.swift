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
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedServiceID)
        .task {
            await viewModel.refresh()
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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
        } else {
            VStack(spacing: 16) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce, options: .repeating)

                Text("No Service Selected")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Select a service from the list to view details.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }

    private var sidebar: some View {
        List {
            Section("Connection") {
                Label(connection.name, systemImage: "server.rack")
                    .foregroundStyle(connection.accentColor)

                if let provider = viewModel.activeProviderName {
                    Label(provider, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("Status") {
                HStack {
                    Text("Connected")
                    Spacer()
                    Circle()
                        .fill(viewModel.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                }

                HStack {
                    Text("Services")
                    Spacer()
                    Text("\(viewModel.services.count)")
                        .foregroundStyle(.secondary)
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
