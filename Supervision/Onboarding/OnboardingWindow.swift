import SwiftUI

struct OnboardingWindow: View {
    @State private var state: OnboardingState
    @ObservedObject private var settings: AppSettings
    @State private var showSkipConfirmation = false
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            progressBar

            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

                switch state.steps[state.currentStepIndex].id {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            navigationBar
        }
        .frame(width: 600, height: 500)
        .alert("Skip Onboarding?", isPresented: $showSkipConfirmation) {
            Button("Skip All") {
                for step in state.steps {
                    step.isSkipped = true
                }
                completeOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can always access setup options from Preferences later.")
        }
        .onChange(of: state.isDismissed) { _, dismissed in
            if dismissed {
                completeOnboarding()
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)

                    Capsule()
                        .fill(.tint)
                        .frame(width: geometry.size.width * state.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: state.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            HStack {
                ForEach(state.steps) { step in
                    HStack(spacing: 6) {
                        stepIcon(step)
                        Text(step.title)
                            .font(.caption)
                            .foregroundStyle(step == state.currentStep ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)

                    if step.id != state.steps.last?.id {
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(.regularMaterial)
    }

    private func stepIcon(_ step: OnboardingStep) -> some View {
        Group {
            if step.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if step.isSkipped {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            } else if step == state.currentStep {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }

    private var navigationBar: some View {
        HStack {
            Button("Skip Step") {
                state.skipCurrent()
            }
            .disabled(state.currentStep.isCompleted || state.currentStep.isSkipped)

            Spacer()

            HStack(spacing: 8) {
                if state.currentStepIndex > 0 {
                    Button("Back") {
                        state.back()
                    }
                }

                Button("Skip All") {
                    showSkipConfirmation = true
                }
                .help("Skip all onboarding steps")

                if state.isLastStep {
                    Button("Get Started") {
                        state.completeCurrent()
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                } else {
                    Button("Continue") {
                        state.completeCurrent()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(!state.currentStep.isValid && !state.currentStep.isSkipped)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.regularMaterial)
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
