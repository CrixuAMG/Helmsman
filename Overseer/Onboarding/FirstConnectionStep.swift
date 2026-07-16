import SwiftUI

struct FirstConnectionStep: View {
    var state: OnboardingState

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .onTapGesture { state.skipCurrent() }
                Spacer()
            }

            Text("Add Your First Connection")
                .font(.title2)
                .fontWeight(.medium)

            Text("Choose a connection method to get started.")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                connectionCard(
                    icon: "bolt.fill",
                    title: "Local",
                    description: "Supervisor running on this machine"
                )
                .padding(.horizontal, 40)

                connectionCard(
                    icon: "network",
                    title: "SSH",
                    description: "Connect to a remote server"
                )
                .padding(.horizontal, 40)

                connectionCard(
                    icon: "shippingbox.fill",
                    title: "Docker",
                    description: "Supervisor inside a container"
                )
                .padding(.horizontal, 40)

                connectionCard(
                    icon: "app.badge.fill",
                    title: "XML-RPC API",
                    description: "Direct API connection"
                )
                .padding(.horizontal, 40)
            }

            Text("You can add connections later from the toolbar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.vertical, 24)
    }

    private func connectionCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(description).font(.callout).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
    }
}
