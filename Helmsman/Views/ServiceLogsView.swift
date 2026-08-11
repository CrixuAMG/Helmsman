import SwiftUI

struct ServiceLogsView: View {
    let service: Service
    let logStore: ProcessLogStore
    let onClear: () -> Void

    @State private var stream: LogStream = .stdout
    @State private var autoScroll = true
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls

            if let error = logStore.lastError(for: service.id, stream: stream),
               logStore.content(for: service.id, stream: stream).isEmpty {
                errorState(error)
            } else if logStore.content(for: service.id, stream: stream).isEmpty {
                emptyState
            } else {
                logText
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Stream", selection: $stream) {
                ForEach(LogStream.allCases) { stream in
                    Text(stream.displayName).tag(stream)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
            .accessibilityLabel("Stream")

            Toggle(isOn: $autoScroll) {
                Label("Follow", systemImage: "arrow.down.to.line")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if let lastFetch = logStore.lastFetchDate(for: service.id, stream: stream) {
                Text("Updated \(lastFetch.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button { showClearConfirmation = true } label: {
                Label("Clear Logs", systemImage: "trash")
            }
            .font(.caption)
            .confirmationDialog("Clear logs?", isPresented: $showClearConfirmation) {
                Button("Clear Logs", role: .destructive, action: onClear)
            } message: {
                Text("All stored log output for this service will be removed.")
            }
        }
    }

    private var logText: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logStore.content(for: service.id, stream: stream))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("log-bottom")
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
            .onChange(of: logStore.content(for: service.id, stream: stream)) { _, _ in
                if autoScroll {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
            .onChange(of: stream) { _, _ in
                if autoScroll {
                    proxy.scrollTo("log-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Waiting for log data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Could not read logs")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
