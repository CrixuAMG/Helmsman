import SwiftUI

struct ServiceListView: View {
    @Bindable var viewModel: MainWindowViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.services.isEmpty && !viewModel.isLoading {
                emptyState
            } else if viewModel.filteredServices.isEmpty && (!viewModel.searchText.isEmpty || viewModel.activeTag != nil) {
                noSearchResults
            } else {
                serviceList
            }
        }

        .searchable(text: $viewModel.searchText, prompt: "Search services")
    }

    private var serviceList: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selectedServiceIDs) {
                ForEach(viewModel.sortedServices) { service in
                    ServiceRowView(
                        service: service,
                        isPerformingAction: viewModel.isPerformingAction(for: service),
                        isFavorite: viewModel.isFavorite(service.id),
                        tags: viewModel.tags(for: service.id),
                        onToggleFavorite: { viewModel.toggleFavorite(for: service.id) },
                        onStart: { viewModel.start(service) },
                        onStop: { viewModel.stop(service) },
                        onRestart: { viewModel.restart(service) }
                    )
                    .tag(service.id)
                    .contextMenu {
                        Button(isFavoriteLabel(service.id)) {
                            viewModel.toggleFavorite(for: service.id)
                        }

                        Divider()

                        Button("Start") { viewModel.start(service) }
                            .disabled(service.status == .running || viewModel.isPerformingAction(for: service))

                        Button("Stop") { viewModel.stop(service) }
                            .disabled(service.status == .stopped || viewModel.isPerformingAction(for: service))

                        Button("Restart") { viewModel.restart(service) }
                            .disabled(viewModel.isPerformingAction(for: service))
                    }

                }
            }
            .listStyle(.inset)

            if viewModel.selectedServices.count > 1 {
                bulkActionBar
            }
        }
    }

    private func isFavoriteLabel(_ serviceID: String) -> String {
        viewModel.isFavorite(serviceID) ? "Remove from Favorites" : "Add to Favorites"
    }

    private var bulkActionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("\(viewModel.selectedServices.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)

                Spacer()

                Button {
                    viewModel.bulkStart()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(viewModel.selectedServices.allSatisfy { $0.status == .running })

                Button {
                    viewModel.bulkStop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(viewModel.selectedServices.allSatisfy { $0.status == .stopped })

                Button {
                    viewModel.bulkRestart()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if viewModel.isBulkActionActive {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var noSearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Matches")
                .font(.headline)

            Text(noResultsDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResultsDescription: String {
        if let activeTag = viewModel.activeTag {
            return "No services are assigned to \"\(activeTag)\"."
        }
        return "No services match \"\(viewModel.searchText)\"."
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
