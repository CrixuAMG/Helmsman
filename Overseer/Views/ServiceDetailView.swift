import SwiftUI

struct ServiceDetailView: View {
    let service: Service
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                statusSection
                Divider()
                detailsSection
                Spacer()
            }
            .padding(24)
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 16) {
            StatusBadge(status: service.status)
                .scaleEffect(1.5)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.name)
                    .font(.title)
                    .fontWeight(.semibold)

                if service.group != service.name {
                    Text(service.group)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Start", action: onStart)
                    .disabled(service.status == .running)

                Button("Stop", action: onStop)
                    .disabled(service.status == .stopped)

                Button("Restart", action: onRestart)
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(service.status.displayName)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)

                Spacer()
            }

            if !service.description.isEmpty {
                Text(service.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                detailRow("PID", value: service.pid > 0 ? "\(service.pid)" : "—")

                detailRow("Uptime", value: formatUptime(service.uptime))

                if let exitStatus = service.exitStatus {
                    detailRow("Exit Status", value: "\(exitStatus)")
                }

                detailRow("Last Updated", value: service.lastUpdated.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .fontWeight(.medium)

            Spacer()
        }
    }

    private var statusColor: Color {
        switch service.status {
        case .running: .green
        case .stopped: .red
        case .starting, .backingoff: .yellow
        case .stopping: .orange
        case .exited: .gray
        case .fatal: .red
        case .unknown: .secondary
        }
    }

    private func formatUptime(_ interval: TimeInterval?) -> String {
        guard let interval = interval, interval > 0 else { return "—" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        return formatter.string(from: interval) ?? "—"
    }
}
