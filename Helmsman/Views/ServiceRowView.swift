import SwiftUI

struct ServiceRowView: View {
    let service: Service
    let isPerformingAction: Bool
    let isFavorite: Bool
    let tags: [String]
    let onToggleFavorite: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: service.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let displayGroup = service.displayGroup {
                    Text(displayGroup)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                .foregroundStyle(Color.accentColor)
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 94, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                     favoriteButton
                     actionButton("play.fill", label: "Start", action: onStart, disabled: service.status == .running, tint: .green)
                     actionButton("stop.fill", label: "Stop", action: onStop, disabled: service.status == .stopped, tint: .red)
                     actionButton("arrow.clockwise", label: "Restart", action: onRestart, disabled: false, tint: .blue)
                }
                .opacity(isHovered ? 1 : 0.6)
            }

        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )

        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isFavorite ? .yellow : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isFavorite ? Color.yellow.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void, disabled: Bool, tint: Color) -> some View {
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
        .help(label)
        .accessibilityLabel(label)

    }
}
