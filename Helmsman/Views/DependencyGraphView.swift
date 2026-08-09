import SwiftUI

struct DependencyGraphView: View {
    let graph: DependencyGraph
    let isEditing: Bool
    let pendingSource: String?
    let selectedNodeID: String?
    let highlightedNodeIDs: Set<String>
    let onSelectNode: (String) -> Void
    let onToggleEdge: (String, String) -> Void

    @State private var canvasSize: CGSize = .zero

    private var layout: GraphLayout {
        GraphLayout(graph: graph)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Canvas { context, _ in
                drawEdges(in: &context)
                drawNodes(in: &context)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location)
            }
        }
    }

    // MARK: - Drawing

    private func drawEdges(in context: inout GraphicsContext) {
        for edge in graph.edges {
            guard let sourceFrame = layout.frame(for: edge.source),
                  let targetFrame = layout.frame(for: edge.target) else { continue }

            let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY)
            let end = CGPoint(x: targetFrame.midX, y: targetFrame.minY)

            var line = Path()
            line.move(to: start)
            line.addLine(to: end)

            let isPending = isEditing && pendingSource == edge.source
            context.stroke(
                line,
                with: .color(isPending ? Color.blue.opacity(0.9) : Color.primary.opacity(0.35)),
                lineWidth: isPending ? 2.5 : 1.5
            )

            drawArrowhead(from: start, to: end, in: &context)
        }
    }

    private func drawArrowhead(from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 8
        let wing: CGFloat = .pi / 6

        let p1 = CGPoint(x: end.x - length * cos(angle - wing), y: end.y - length * sin(angle - wing))
        let p2 = CGPoint(x: end.x - length * cos(angle + wing), y: end.y - length * sin(angle + wing))

        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: p1)
        arrow.addLine(to: p2)
        arrow.closeSubpath()

        context.fill(arrow, with: .color(Color.primary.opacity(0.5)))
    }

    private func drawNodes(in context: inout GraphicsContext) {
        for node in graph.sortedNodes {
            guard let frame = layout.frame(for: node.id) else { continue }

            let isSelected = node.id == selectedNodeID
            let isPending = isEditing && node.id == pendingSource
            let isHighlighted = highlightedNodeIDs.contains(node.id)

            let fill = isHighlighted
                ? Color.purple.opacity(0.28)
                : statusColor(node.status).opacity(isSelected ? 0.28 : 0.14)
            let border = isPending
                ? Color.blue
                : (isHighlighted ? Color.purple : (isSelected ? Color.accentColor : statusColor(node.status).opacity(0.6)))

            let rounded = RoundedRectangle(cornerRadius: 8, style: .continuous)
            context.fill(rounded.path(in: frame), with: .color(fill))
            context.stroke(rounded.path(in: frame), with: .color(border), lineWidth: isSelected || isPending || isHighlighted ? 2 : 1)

            let label = Text(node.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            context.draw(label, at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)

            if node.isFavorite {
                context.draw(
                    Text(Image(systemName: "star.fill"))
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow),
                    at: CGPoint(x: frame.maxX - 9, y: frame.minY + 9)
                )
            }
        }
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint) {
        guard let tapped = graph.nodes.first(where: { layout.frame(for: $0.id)?.contains(location) == true }) else {
            return
        }

        if isEditing {
            onToggleEdge(tapped.id, tapped.id)
        } else {
            onSelectNode(tapped.id)
        }
    }

    private func statusColor(_ status: ServiceStatus) -> Color {
        switch status {
        case .running: .green
        case .stopped: .red
        case .starting, .backingoff: .orange
        case .stopping: .yellow
        case .exited: .gray
        case .fatal: .red
        case .unknown: .gray
        }
    }
}

// MARK: - Layout

private struct GraphLayout {
    let graph: DependencyGraph
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat = 44
    let hSpacing: CGFloat = 24
    let vSpacing: CGFloat = 56
    let padding: CGFloat = 24

    init(graph: DependencyGraph) {
        self.graph = graph
        let longest = graph.nodes.map(\.name).map { $0.count }.max() ?? 0
        self.nodeWidth = max(120, CGFloat(longest) * 7.5 + 40)
    }

    private var nodesByLevel: [Int: [DependencyGraphNode]] {
        Dictionary(grouping: graph.sortedNodes) { graph.levels[$0.id] ?? 0 }
    }

    var size: CGSize {
        let maxCount = nodesByLevel.values.map(\.count).max() ?? 0
        let width = padding * 2 + CGFloat(maxCount) * (nodeWidth + hSpacing) - hSpacing
        let height = padding * 2 + CGFloat(graph.maxLevel + 1) * (nodeHeight + vSpacing) - vSpacing
        return CGSize(width: max(width, 120), height: max(height, 80))
    }

    func frame(for id: String) -> CGRect? {
        guard graph.nodes.contains(where: { $0.id == id }) else { return nil }
        let level = graph.levels[id] ?? 0
        let siblings = nodesByLevel[level] ?? []
        let index = siblings.firstIndex { $0.id == id } ?? 0
        let x = padding + CGFloat(index) * (nodeWidth + hSpacing)
        let y = padding + CGFloat(level) * (nodeHeight + vSpacing)
        return CGRect(x: x, y: y, width: nodeWidth, height: nodeHeight)
    }
}
