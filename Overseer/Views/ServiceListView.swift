import SwiftUI

struct ServiceListView: View {
    @Bindable var viewModel: MainWindowViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.services.isEmpty && !viewModel.isLoading {
                emptyState
                    .transition(.opacity.combined(with: .scale))
            } else {
                serviceList
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.services.isEmpty)
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
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .listStyle(.inset)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.filteredServices)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let error = viewModel.lastError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating)

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
                    .symbolEffect(.bounce, options: .repeating)

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
