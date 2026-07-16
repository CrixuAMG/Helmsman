import SwiftUI

struct StatusBadge: View {
    let status: ServiceStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0 : 0.6)

            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            if status == .running || status == .starting {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .running || newStatus == .starting {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
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
