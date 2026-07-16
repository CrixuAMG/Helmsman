import SwiftUI

struct ServiceRowView: View {
    let service: Service
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: service.status)

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
                actionButton("play.fill", action: onStart, disabled: service.status == .running)
                actionButton("stop.fill", action: onStop, disabled: service.status == .stopped)
                actionButton("arrow.clockwise", action: onRestart, disabled: false)
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(_ icon: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
    }
}
