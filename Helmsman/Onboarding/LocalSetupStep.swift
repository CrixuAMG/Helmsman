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
        OnboardingStepPage(
            systemImage: "terminal.fill",
            title: "Find Supervisor",
            subtitle: "Helmsman looks for supervisorctl so it can manage services running on this Mac."
        ) {
            statusView

            if showPathInput {
                customPathEntry
            }
        }
        .task {
            await searchForSupervisor()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .waiting, .checking:
            OnboardingCard {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching common install locations")
                            .fontWeight(.medium)
                        Text("Checking Homebrew and system paths for supervisorctl.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        case .success(let path):
            OnboardingCard {
                OnboardingListRow(
                    systemImage: "checkmark.circle.fill",
                    title: "supervisorctl found",
                    description: path,
                    accessorySystemImage: "checkmark",
                    accessoryColor: .green
                )
            }
        case .notFound(let message):
            OnboardingCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("supervisorctl not found")
                                .fontWeight(.medium)
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Search Again") {
                            Task { await searchForSupervisor() }
                        }

                        Button("Enter Path Manually") {
                            showPathInput = true
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private var customPathEntry: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Path")
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    TextField("Path to supervisorctl", text: $supervisorPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Verify") {
                        Task { await verifyCustomPath() }
                    }
                    .disabled(supervisorPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("Common paths include /usr/local/bin/supervisorctl and /opt/homebrew/bin/supervisorctl.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func searchForSupervisor() async {
        status = .checking
        showPathInput = false

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
                showPathInput = true
            }
            return
        }

        await MainActor.run {
            status = .success(path)
            showPathInput = false
            state.currentStep.isCompleted = true
        }
    }
}
