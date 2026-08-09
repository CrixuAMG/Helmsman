import SwiftUI

struct ServiceTimelineView: View {
    let service: Service
    let eventStore: ProcessEventStore
    let metricsStore: ProcessMetricsStore
    let memoryDisplayUnit: MemoryDisplayUnit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statsSection
                Divider()
                eventsSection
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Statistics

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Uptime", value: formatUptime(service.uptime), icon: "clock", color: .green)
                statCard(title: "Restarts", value: "\(eventStore.restartCount(for: service.id))", icon: "arrow.clockwise", color: .blue)
                statCard(title: "Crashes", value: "\(eventStore.crashCount(for: service.id))", icon: "exclamationmark.triangle", color: .orange)
                statCard(title: "Avg. Runtime", value: formatDuration(eventStore.averageRuntime(for: service.id)), icon: "timer", color: .purple)

                if let latest = metricsStore.getLatest(for: service.id) {
                    statCard(title: "CPU", value: String(format: "%.1f%%", latest.cpuPercent), icon: "cpu", color: .green)
                    statCard(title: "Memory", value: formatMemory(latest.memoryMB), icon: "memorychip", color: .blue)
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Events

    private var eventsSection: some View {
        let events = eventStore.events(for: service.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if !events.isEmpty {
                    Button("Clear") {
                        eventStore.clear(for: service.id)
                    }
                    .font(.caption)
                }
            }

            if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No lifecycle events recorded yet.\nEvents appear as the service changes state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
            } else {
                eventTimeline(events: events)
            }
        }
    }

    private func eventTimeline(events: [ProcessEvent]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(color(for: event.kind))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(.background, lineWidth: 2)
                            )
                        if index < events.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(width: 2, height: 42)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 6) {
                            Image(systemName: event.kind.systemImage)
                                .font(.caption)
                                .foregroundStyle(color(for: event.kind))
                            Text(event.kind.displayName)
                                .font(.body)
                                .fontWeight(.medium)
                        }

                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func color(for kind: ProcessEventKind) -> Color {
        switch kind {
        case .started: .green
        case .running: .green
        case .stopped: .red
        case .crashed: .orange
        case .restarted: .blue
        case .exited: .gray
        case .fatal: .red
        case .backingoff: .yellow
        case .unknown: .secondary
        }
    }

    private func formatUptime(_ interval: TimeInterval?) -> String {
        guard let interval = interval, interval > 0 else { return "—" }
        return formatDuration(interval)
    }

    private func formatDuration(_ interval: TimeInterval?) -> String {
        guard let interval = interval, interval > 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "—"
    }

    private func formatMemory(_ mb: Double) -> String {
        switch memoryDisplayUnit {
        case .megabytes:
            return String(format: "%.1f MB", mb)
        case .gigabytes:
            return String(format: "%.2f GB", mb / 1024.0)
        }
    }
}
