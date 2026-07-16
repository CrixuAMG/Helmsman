import SwiftUI

struct StatusBadge: View {
    let status: ServiceStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 3)
            )
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .stopped: .red
        case .starting, .backingoff: .yellow
        case .stopping: .orange
        case .exited: .gray
        case .fatal: .red
        case .unknown: .secondary
        }
    }
}
