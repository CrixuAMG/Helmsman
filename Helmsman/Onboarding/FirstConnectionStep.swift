import SwiftUI

struct FirstConnectionStep: View {
    var state: OnboardingState

    var body: some View {
        OnboardingStepPage(
            systemImage: "server.rack",
            title: "Choose connection types",
            subtitle: "Helmsman can connect in several ways. Add your first connection after onboarding, or skip this step for now."
        ) {
            OnboardingCard {
                connectionRow(icon: "bolt.fill", title: "Local", description: "Supervisor running on this machine")
                OnboardingDivider()
                connectionRow(icon: "network", title: "SSH", description: "Connect to a remote server")
                OnboardingDivider()
                connectionRow(icon: "shippingbox.fill", title: "Docker", description: "Supervisor inside a container")
                OnboardingDivider()
                connectionRow(icon: "app.badge.fill", title: "XML-RPC API", description: "Direct API connection")
            }

            Text("Connections can always be added later from the Connections window toolbar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func connectionRow(icon: String, title: String, description: String) -> some View {
        OnboardingListRow(
            systemImage: icon,
            title: title,
            description: description,
            accessorySystemImage: "plus.circle",
            accessoryColor: .secondary
        )
    }
}
