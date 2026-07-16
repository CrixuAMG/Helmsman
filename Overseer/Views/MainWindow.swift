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
        } detail: {
            ServiceListView(viewModel: viewModel)
        }
        .navigationTitle(connection.name)
        .toolbar {
            toolbarContent
        }
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
