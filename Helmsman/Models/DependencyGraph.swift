import Foundation

struct DependencyEdge: Codable, Hashable, Sendable {
    /// Service that depends on `target`.
    let source: String
    /// Service that `source` depends on (rendered below `source`).
    let target: String

    var key: String { "\(source)→\(target)" }
}

struct DependencyGraphNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String
    let status: ServiceStatus
    let isFavorite: Bool
}

struct DependencyGraph: Sendable {
    let nodes: [DependencyGraphNode]
    let edges: [DependencyEdge]
    /// node id → level, where 0 is the top of the graph.
    let levels: [String: Int]

    var sortedNodes: [DependencyGraphNode] {
        nodes.sorted { lhs, rhs in
            let levelOrder = levels[lhs.id] ?? 0
            let rhsLevel = levels[rhs.id] ?? 0
            if levelOrder != rhsLevel { return levelOrder < rhsLevel }
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.name < rhs.name
        }
    }

    var maxLevel: Int {
        levels.values.max() ?? 0
    }

    static func build(services: [Service], edges: [DependencyEdge], favorites: Set<String>) -> DependencyGraph {
        let nodes = services.map { service in
            DependencyGraphNode(
                id: service.controlName,
                name: service.name,
                group: service.group,
                status: service.status,
                isFavorite: favorites.contains(service.id)
            )
        }
        let ids = Set(nodes.map(\.id))
        let validEdges = edges.filter { ids.contains($0.source) && ids.contains($0.target) }

        var levels: [String: Int] = [:]
        var changed = true
        var iterations = 0

        while changed && iterations <= nodes.count {
            changed = false
            for edge in validEdges {
                let sourceLevel = levels[edge.source] ?? 0
                let candidate = sourceLevel + 1
                if (levels[edge.target] ?? 0) < candidate {
                    levels[edge.target] = candidate
                    changed = true
                }
            }
            iterations += 1
        }

        return DependencyGraph(nodes: nodes, edges: validEdges, levels: levels)
    }
}
