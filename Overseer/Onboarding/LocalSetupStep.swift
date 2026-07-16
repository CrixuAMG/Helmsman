import SwiftUI

struct LocalSetupStep: View {
    var state: OnboardingState
    @State private var supervisorPath: String = ""
    @State private var status: SetupStatus = .waiting
    @State private var showPathInput = false

    enum SetupStatus: Equatable {
        case waiting, checking, success(String), notFound(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .onTapGesture { state.skipCurrent() }
                Spacer()
            }

            Image(systemName: "terminal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Find Supervisor")
                .font(.title2)
                .fontWeight(.medium)

            Text("Locate your supervisorctl binary to manage local services.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            statusView

            if status == .waiting {
                if showPathInput {
                    customPathEntry
                } else {
                    Button("Search Again") {
                        Task { await searchForSupervisor() }
                    }
                }
            }

            Spacer()
        }
        .padding(32)
        .task {
            await searchForSupervisor()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .waiting:
            ProgressView()
                .controlSize(.regular)
        case .checking:
            ProgressView()
                .controlSize(.regular)
        case .success(let path):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("supervisorctl found")
                        .fontWeight(.medium)
                    Text(path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.green.opacity(0.1))
            )
        case .notFound(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("supervisorctl not found")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Enter Path Manually") {
                    showPathInput = true
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.yellow.opacity(0.1))
            )
        }
    }

    private var customPathEntry: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Path to supervisorctl", text: $supervisorPath)
                    .textFieldStyle(.roundedBorder)
                Button("Verify") {
                    Task { await verifyCustomPath() }
                }
            }

            Text("Try: /usr/local/bin/supervisorctl, /opt/homebrew/bin/supervisorctl, /usr/bin/supervisorctl")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func searchForSupervisor() async {
        status = .checking

        let searchPaths = ["/opt/homebrew/bin/supervisorctl", "/usr/local/bin/supervisorctl", "/usr/bin/supervisorctl"]

        let foundPath = searchPaths.first { path in
            FileManager.default.isExecutableFile(atPath: path)
        }

        if let path = foundPath {
            await MainActor.run {
                status = .success(path)
                state.currentStep.isCompleted = true
            }
        } else {
            await MainActor.run {
                status = .notFound("Checked: \(searchPaths.joined(separator: ", "))")
                showPathInput = true
            }
        }
    }

    private func verifyCustomPath() async {
        let path = supervisorPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            await MainActor.run {
                status = .notFound("File not found or not executable: \(path)")
            }
            return
        }

        await MainActor.run {
            status = .success(path)
            state.currentStep.isCompleted = true
        }
    }
}
