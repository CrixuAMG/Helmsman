import SwiftUI
import SwiftData

struct DependencyGraphSheetView: View {
    @Bindable var viewModel: MainWindowViewModel
    let connection: Connection

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var pendingSource: String?
    @State private var highlightedTag: String?

    private var graph: DependencyGraph {
        DependencyGraph.build(
            services: viewModel.services,
            edges: connection.dependencyEdges,
            favorites: connection.favoriteServiceIDs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            if viewModel.services.isEmpty {
                emptyState
            } else {
                DependencyGraphView(
                    graph: graph,
                    isEditing: isEditing,
                    pendingSource: pendingSource,
                    selectedNodeID: pendingSource ?? (viewModel.selectedServiceIDs.count == 1 ? viewModel.selectedServiceIDs.first : nil),
                    highlightedNodeIDs: highlightedNodeIDs,
                    onSelectNode: { nodeID in
                        if let service = viewModel.services.first(where: { $0.controlName == nodeID }) {
                            viewModel.selectedServiceIDs = [service.id]
                        }
                    },
                    onToggleEdge: { source, target in
                        handleToggle(source: source, target: target)
                    }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(connection.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dependency Graph")
                    .font(.headline)
                Text(connection.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("None") { highlightedTag = nil }
                if !connection.tagNames.isEmpty {
                    Divider()
                    ForEach(connection.tagNames, id: \.self) { tag in
                        Button {
                            highlightedTag = tag
                        } label: {
                            Label(tag, systemImage: highlightedTag == tag ? "checkmark" : "tag")
                        }
                    }
                }
            } label: {
                Label(highlightedTag.map { "Highlight: \($0)" } ?? "Highlight Tag", systemImage: "tag")
            }

            if isEditing {
                Text(pendingSource == nil
                     ? "Select the service that depends on another"
                     : "Now select the service it depends on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(isEditing ? "Done" : "Edit") {
                isEditing.toggle()
                pendingSource = nil
            }

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var highlightedNodeIDs: Set<String> {
        guard let highlightedTag else { return [] }
        let taggedIDs = connection.processTags[highlightedTag] ?? []
        return Set(viewModel.services.filter { taggedIDs.contains($0.id) }.map(\.controlName))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No services loaded")
                .font(.headline)
            Text("Connect to a running Supervisor instance to build a dependency graph.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleToggle(source: String, target: String) {
        guard isEditing else { return }

        if pendingSource == nil {
            pendingSource = source
            return
        }

        guard let pending = pendingSource else { return }

        if pending == target {
            pendingSource = nil
            return
        }

        if connection.dependencyEdges.contains(where: { $0.source == pending && $0.target == target }) {
            connection.removeDependency(from: pending, to: target)
        } else {
            connection.addDependency(from: pending, to: target)
        }

        try? modelContext.save()
        pendingSource = nil
    }
}
