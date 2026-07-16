import SwiftUI

struct ServiceRowView: View {
    let service: Service
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: service.status)
                .animation(.easeInOut(duration: 0.3), value: service.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if service.group != service.name {
                    Text(service.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                actionButton("play.fill", action: onStart, disabled: service.status == .running, tint: .green)
                actionButton("stop.fill", action: onStop, disabled: service.status == .stopped, tint: .red)
                actionButton("arrow.clockwise", action: onRestart, disabled: false, tint: .blue)
            }
            .opacity(isHovered ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func actionButton(_ icon: String, action: @escaping () -> Void, disabled: Bool, tint: Color) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? .secondary : tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(disabled ? Color.clear : tint.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .scaleEffect(disabled ? 1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: disabled)
    }
}
