import AtollExtensionKit
import Foundation

enum CodexAccentTheme: String, CaseIterable, Sendable {
    case lavender
    case ocean
    case mint
    case rose
    case amber

    var cssColor: String {
        switch self {
        case .lavender: return "#8f7dff"
        case .ocean: return "#55b8ff"
        case .mint: return "#5de6a0"
        case .rose: return "#ff79a8"
        case .amber: return "#ffb84d"
        }
    }

    var atollColor: AtollColorDescriptor {
        switch self {
        case .lavender: return .init(red: 0.56, green: 0.49, blue: 1)
        case .ocean: return .init(red: 0.33, green: 0.72, blue: 1)
        case .mint: return .init(red: 0.36, green: 0.90, blue: 0.63)
        case .rose: return .init(red: 1, green: 0.47, blue: 0.66)
        case .amber: return .init(red: 1, green: 0.72, blue: 0.30)
        }
    }
}

enum CodexDashboardTextSize: String, CaseIterable, Sendable {
    case system
    case large
    case extraLarge

    var cssScale: Double {
        switch self {
        case .system: return 1.0
        case .large: return 1.14
        case .extraLarge: return 1.28
        }
    }

    var label: String {
        switch self {
        case .system: return "A"
        case .large: return "A+"
        case .extraLarge: return "A++"
        }
    }
}

final class CodexDashboardPreferences: @unchecked Sendable {
    private let defaults = UserDefaults(suiteName: "com.tibetgao.CodexQuotaAtoll") ?? .standard
    private let accentKey = "dashboardAccentTheme"
    private let textSizeKey = "dashboardTextSize"

    var accentTheme: CodexAccentTheme {
        get { CodexAccentTheme(rawValue: defaults.string(forKey: accentKey) ?? "") ?? .lavender }
        set { defaults.set(newValue.rawValue, forKey: accentKey) }
    }

    var textSize: CodexDashboardTextSize {
        get { CodexDashboardTextSize(rawValue: defaults.string(forKey: textSizeKey) ?? "") ?? .large }
        set { defaults.set(newValue.rawValue, forKey: textSizeKey) }
    }
}
