import SwiftUI

struct ServiceListView: View {
    @Bindable var viewModel: MainWindowViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.services.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                serviceList
            }
        }

        .searchable(text: $viewModel.searchText, prompt: "Search services")
    }

    private var serviceList: some View {
        List(selection: $viewModel.selectedServiceID) {
            ForEach(viewModel.filteredServices) { service in
                ServiceRowView(
                    service: service,
                    onStart: { viewModel.start(service) },
                    onStop: { viewModel.stop(service) },
                    onRestart: { viewModel.restart(service) }
                )
                .tag(service.id)
                .contextMenu {
                    Button("Start") { viewModel.start(service) }
                        .disabled(service.status == .running)

                    Button("Stop") { viewModel.stop(service) }
                        .disabled(service.status == .stopped)

                    Button("Restart") { viewModel.restart(service) }
                }

            }
        }
        .listStyle(.inset)

    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let error = viewModel.lastError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
    

                Text("Connection Error")
                    .font(.title2)
                    .fontWeight(.medium)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)

                    Button("Reconnect") {
                        Task { await viewModel.reconnect() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)


                Text("No Services")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("No Supervisor services found on this connection.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
