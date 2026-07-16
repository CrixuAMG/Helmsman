import SwiftUI

struct AppearanceStep: View {
    var state: OnboardingState
    @ObservedObject private var settings: AppSettings

    init(state: OnboardingState, settings: AppSettings) {
        self.state = state
        self.settings = settings
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

            Image(systemName: "paintbrush.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Choose Appearance")
                .font(.title2)
                .fontWeight(.medium)

            VStack(spacing: 12) {
                themeOption(
                    icon: "sun.max.fill",
                    title: "Light",
                    description: "Classic light appearance",
                    theme: .light,
                    isSelected: settings.theme == .light
                ) {
                    settings.theme = .light
                }

                themeOption(
                    icon: "moon.fill",
                    title: "Dark",
                    description: "Easy on the eyes",
                    theme: .dark,
                    isSelected: settings.theme == .dark
                ) {
                    settings.theme = .dark
                }

                themeOption(
                    icon: "circle.lefthalf.filled",
                    title: "System",
                    description: "Follow macOS appearance",
                    theme: .system,
                    isSelected: settings.theme == .system
                ) {
                    settings.theme = .system
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.vertical, 24)
    }

    private func themeOption(
        icon: String,
        title: String,
        description: String,
        theme: AppTheme,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(description).font(.callout).foregroundStyle(Color.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
