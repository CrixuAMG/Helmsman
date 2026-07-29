import SwiftUI

struct AppearanceStep: View {
    var state: OnboardingState
    @ObservedObject private var settings: AppSettings

    init(state: OnboardingState, settings: AppSettings) {
        self.state = state
        self.settings = settings
    }

    var body: some View {
        OnboardingStepPage(
            systemImage: "paintbrush.fill",
            title: "Choose appearance",
            subtitle: "Pick the look that fits your desktop. This can be changed later in Settings."
        ) {
            OnboardingCard {
                themeOption(
                    icon: "circle.lefthalf.filled",
                    title: "System",
                    description: "Follow the current macOS appearance",
                    theme: .system,
                    isSelected: settings.theme == .system
                )

                OnboardingDivider()

                themeOption(
                    icon: "sun.max.fill",
                    title: "Light",
                    description: "Use the classic light appearance",
                    theme: .light,
                    isSelected: settings.theme == .light
                )

                OnboardingDivider()

                themeOption(
                    icon: "moon.fill",
                    title: "Dark",
                    description: "Use a darker appearance",
                    theme: .dark,
                    isSelected: settings.theme == .dark
                )
            }
        }
    }

    private func themeOption(
        icon: String,
        title: String,
        description: String,
        theme: AppTheme,
        isSelected: Bool
    ) -> some View {
        Button {
            settings.theme = theme
        } label: {
            OnboardingListRow(
                systemImage: icon,
                title: title,
                description: description,
                accessorySystemImage: isSelected ? "checkmark.circle.fill" : "circle",
                accessoryColor: isSelected ? .accentColor : .secondary
            )
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Color.accentColor.opacity(0.08)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
