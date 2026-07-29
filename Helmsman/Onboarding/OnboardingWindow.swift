import SwiftUI

struct OnboardingWindow: View {
    @State private var state: OnboardingState
    @ObservedObject private var settings: AppSettings
    @State private var showSkipConfirmation = false

    private let onDismiss: () -> Void

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss
        let steps = [
            OnboardingStep(id: "welcome", title: "Welcome"),
            OnboardingStep(id: "local-setup", title: "Local Setup"),
            OnboardingStep(id: "first-connection", title: "Connections"),
            OnboardingStep(id: "appearance", title: "Appearance"),
        ]
        _state = State(initialValue: OnboardingState(steps: steps))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    currentStepView
                        .id(state.currentStep.id)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: state.currentStep.id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                navigationBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 28, y: 18)
        .alert("Skip Onboarding?", isPresented: $showSkipConfirmation) {
            Button("Skip All") {
                for step in state.steps {
                    step.isSkipped = true
                }
                completeOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can always access setup options from Settings later.")
        }
        .onChange(of: state.isDismissed) { _, dismissed in
            if dismissed {
                completeOnboarding()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Helmsman")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Setup Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.horizontal, 22)

            VStack(spacing: 4) {
                ForEach(Array(state.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, index: index)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            ProgressView(value: state.progress)
                .controlSize(.small)
                .padding(.horizontal, 22)

            Text("Step \(state.currentStepIndex + 1) of \(state.steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
    }

    private func stepRow(_ step: OnboardingStep, index: Int) -> some View {
        let isCurrent = step == state.currentStep

        return HStack(spacing: 10) {
            stepIcon(step, index: index)
                .frame(width: 22, height: 22)

            Text(step.title)
                .font(.callout)
                .fontWeight(isCurrent ? .medium : .regular)
                .foregroundStyle(isCurrent ? .primary : .secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
    }

    private func stepIcon(_ step: OnboardingStep, index: Int) -> some View {
        Group {
            if step.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if step.isSkipped {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            } else if step == state.currentStep {
                Image(systemName: stepSymbol(for: step))
                    .foregroundStyle(.tint)
            } else {
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
        }
        .font(.callout)
        .symbolRenderingMode(.hierarchical)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch state.currentStep.id {
        case "welcome":
            WelcomeStep(state: state)
        case "local-setup":
            LocalSetupStep(state: state)
        case "first-connection":
            FirstConnectionStep(state: state)
        case "appearance":
            AppearanceStep(state: state, settings: settings)
        default:
            EmptyView()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button("Skip Step") {
                state.skipCurrent()
            }
            .disabled(state.currentStep.isCompleted || state.currentStep.isSkipped)

            Spacer()

            if state.currentStepIndex > 0 {
                Button("Back") {
                    state.back()
                }
            }

            Button("Skip All") {
                showSkipConfirmation = true
            }
            .help("Skip all onboarding steps")

            Button(state.isLastStep ? "Get Started" : "Continue") {
                if state.isLastStep {
                    state.completeCurrent()
                    completeOnboarding()
                } else {
                    state.completeCurrent()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!state.currentStep.isValid && !state.currentStep.isSkipped)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func stepSymbol(for step: OnboardingStep) -> String {
        switch step.id {
        case "welcome": "eye.fill"
        case "local-setup": "terminal.fill"
        case "first-connection": "server.rack"
        case "appearance": "paintbrush.fill"
        default: "circle.fill"
        }
    }

    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        onDismiss()
    }
}

extension OnboardingStep: Identifiable {}
extension OnboardingStep: Equatable {
    static func == (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.id == rhs.id
    }
}
