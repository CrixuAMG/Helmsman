import SwiftUI

struct WelcomeStep: View {
    var state: OnboardingState

    var body: some View {
        OnboardingStepPage(
            systemImage: "eye.fill",
            title: "Welcome to Helmsman",
            subtitle: "Manage local and remote Supervisor services from one focused macOS app."
        ) {
            OnboardingCard {
                featureRow(icon: "bolt.fill", title: "Local Processes", description: "Manage Supervisor running on this Mac")
                OnboardingDivider()
                featureRow(icon: "network", title: "SSH Connections", description: "Control remote servers over SSH")
                OnboardingDivider()
                featureRow(icon: "shippingbox.fill", title: "Docker", description: "Manage services inside Docker containers")
                OnboardingDivider()
                featureRow(icon: "app.badge.fill", title: "XML-RPC API", description: "Connect to Supervisor's XML-RPC interface")
            }
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        OnboardingListRow(
            systemImage: icon,
            title: title,
            description: description,
            accessorySystemImage: "checkmark.circle.fill",
            accessoryColor: .green
        )
    }
}
