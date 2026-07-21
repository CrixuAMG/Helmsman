import SwiftUI

struct WelcomeStep: View {
    var state: OnboardingState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.top, 20)

            Text("Welcome to Helmsman")
                .font(.title2)
                .fontWeight(.medium)

            Text("The modern way to manage your Supervisor services.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                featureRow(icon: "bolt.fill", title: "Local Processes", description: "Manage Supervisor running on this Mac")
                featureRow(icon: "network", title: "SSH Connections", description: "Control remote servers over SSH")
                featureRow(icon: "shippingbox.fill", title: "Docker", description: "Manage services inside Docker containers")
                featureRow(icon: "app.badge.fill", title: "XML-RPC API", description: "Connect to Supervisor's XML-RPC interface")
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
        }
        .padding(.horizontal, 32)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(description).font(.callout).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
    }
}
