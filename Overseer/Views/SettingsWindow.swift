import SwiftUI

struct SettingsWindow: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView(settings: settings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 280)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Defaults for New Connections") {
                HStack {
                    Text("Polling Interval")
                    Spacer()
                    TextField("", value: $settings.defaultPollingInterval, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Timeout")
                    Spacer()
                    TextField("", value: $settings.defaultTimeout, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }

                Toggle("Safe Mode", isOn: $settings.defaultSafeMode)
                Toggle("Auto Reconnect", isOn: $settings.defaultAutoReconnect)
            }

            Section {
                Button("Restart Onboarding") {
                    settings.hasCompletedOnboarding = false
                    NSApplication.shared.terminate(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
                .foregroundStyle(.red)
            } footer: {
                Text("The app will quit. Reopen it to see the onboarding flow again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
