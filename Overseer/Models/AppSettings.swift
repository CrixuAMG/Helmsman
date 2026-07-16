import Foundation
import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app.theme") }
    }

    @Published var defaultPollingInterval: TimeInterval {
        didSet { UserDefaults.standard.set(defaultPollingInterval, forKey: "app.defaultPollingInterval") }
    }

    @Published var defaultSafeMode: Bool {
        didSet { UserDefaults.standard.set(defaultSafeMode, forKey: "app.defaultSafeMode") }
    }

    @Published var defaultAutoReconnect: Bool {
        didSet { UserDefaults.standard.set(defaultAutoReconnect, forKey: "app.defaultAutoReconnect") }
    }

    @Published var defaultTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(defaultTimeout, forKey: "app.defaultTimeout") }
    }

    private init() {
        let defaults = UserDefaults.standard

        self.theme = AppTheme(rawValue: defaults.string(forKey: "app.theme") ?? "") ?? .system
        self.defaultPollingInterval = defaults.object(forKey: "app.defaultPollingInterval") as? TimeInterval ?? 5
        self.defaultSafeMode = defaults.object(forKey: "app.defaultSafeMode") as? Bool ?? true
        self.defaultAutoReconnect = defaults.object(forKey: "app.defaultAutoReconnect") as? Bool ?? true
        self.defaultTimeout = defaults.object(forKey: "app.defaultTimeout") as? TimeInterval ?? 30
    }
}
