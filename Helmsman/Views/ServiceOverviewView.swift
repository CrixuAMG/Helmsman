import SwiftUI
import Charts

struct ServiceOverviewView: View {
    let service: Service
    let metricsStore: ProcessMetricsStore
    let memoryDisplayUnit: MemoryDisplayUnit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusSection
                Divider()
                detailsSection
                Divider()
                metricsGraphSection
                Spacer(minLength: 0)
            }
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

            VStack(spacing: 0) {
                detailRow("PID", value: service.pid > 0 ? "\(service.pid)" : "—")
                Divider().padding(.leading, 120)
                detailRow("Uptime", value: formatUptime(service.uptime))

                if let exitStatus = service.exitStatus {
                    Divider().padding(.leading, 120)
                    detailRow("Exit Status", value: "\(exitStatus)")
                }

                Divider().padding(.leading, 120)

                if let latest = metricsStore.getLatest(for: service.id) {
                    let cpuStr = String(format: "%.1f%%", latest.cpuPercent)
                    let memStr = formatMemory(latest.memoryMB)
                    detailRow("CPU", value: cpuStr)
                    Divider().padding(.leading, 120)
                    detailRow("Memory", value: memStr)
                } else if service.status == .running && service.pid > 0 {
                    detailRow("CPU", value: "Collecting...")
                    Divider().padding(.leading, 120)
                    detailRow("Memory", value: "Collecting...")
                } else {
                    detailRow("CPU", value: "—")
                    Divider().padding(.leading, 120)
                    detailRow("Memory", value: "—")
                }

                Divider().padding(.leading, 120)
                detailRow("Last Updated", value: service.lastUpdated.formatted(date: .abbreviated, time: .standard))
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    private var metricsGraphSection: some View {
        let history = metricsStore.getHistory(for: service.id)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Resource Usage (Last 30 Minutes)")
                .font(.headline)
                .foregroundStyle(.secondary)

            metricsDisclaimer(history: history)

            if history.isEmpty {
                if service.status == .running && service.pid > 0 {
                    emptyGraphPlaceholder
                } else {
                    notRunningPlaceholder
                }
            } else {
                cpuGraph(history: history)
                memoryGraph(history: history)
            }
        }
    }

    @ViewBuilder
    private func metricsDisclaimer(history: [ProcessMetrics]) -> some View {
        if service.status != .running || service.pid == 0 {
            Label(history.isEmpty ? "Process not running" : "Process not running - showing last known data", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.yellow.opacity(0.1))
                )
        } else if let latest = history.last,
                  Date().timeIntervalSince(latest.timestamp) > 120 {
            Label("Metrics are stale", systemImage: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.orange.opacity(0.1))
                )
        } else if history.isEmpty {
            Label("Waiting for data...", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.1))
                )
        }
    }

    private func cpuGraph(history: [ProcessMetrics]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            graphHeader(title: "CPU", value: latestCPUText(from: history), color: .green)

            Chart(history) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuPercent)
                )
                .foregroundStyle(.green.opacity(0.15))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuPercent)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: chartTimeRange)
            .chartYScale(domain: 0...cpuUpperBound(for: history))
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func memoryGraph(history: [ProcessMetrics]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            graphHeader(title: "Memory", value: latestMemoryText(from: history), color: .blue)

            Chart(history) { point in
                let yValue = memoryValue(for: point)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", yValue)
                )
                .foregroundStyle(.blue.opacity(0.15))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", yValue)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: chartTimeRange)
            .chartYScale(domain: 0...memoryUpperBound(for: history))
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var chartTimeRange: ClosedRange<Date> {
        let end = Date()
        return end.addingTimeInterval(-1800)...end
    }

    private func graphHeader(title: String, value: String, color: Color) -> some View {
        HStack {
            Label(title, systemImage: "chart.xyaxis.line")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    private func latestCPUText(from history: [ProcessMetrics]) -> String {
        guard let latest = history.last else { return "--" }
        return String(format: "%.1f%%", latest.cpuPercent)
    }

    private func latestMemoryText(from history: [ProcessMetrics]) -> String {
        guard let latest = history.last else { return "--" }
        return formatMemory(latest.memoryMB)
    }

    private func memoryValue(for point: ProcessMetrics) -> Double {
        memoryDisplayUnit == .gigabytes ? point.memoryMB / 1024.0 : point.memoryMB
    }

    private func cpuUpperBound(for history: [ProcessMetrics]) -> Double {
        let maximum = history.map(\.cpuPercent).max() ?? 0
        return max(100, (maximum / 25).rounded(.up) * 25)
    }

    private func memoryUpperBound(for history: [ProcessMetrics]) -> Double {
        let maximum = history.map { memoryValue(for: $0) }.max() ?? 0
        let step = memoryDisplayUnit == .gigabytes ? 0.25 : 128.0
        return max(step, (maximum / step).rounded(.up) * step)
    }

    private var emptyGraphPlaceholder: some View {
        VStack {
            Spacer()
            Text("No data yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }

    private var notRunningPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Process not running")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    private func formatMemory(_ mb: Double) -> String {
        switch memoryDisplayUnit {
        case .megabytes:
            return String(format: "%.1f MB", mb)
        case .gigabytes:
            return String(format: "%.2f GB", mb / 1024.0)
        }
    }
}
