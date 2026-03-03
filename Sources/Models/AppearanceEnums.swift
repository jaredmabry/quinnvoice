import SwiftUI

// MARK: - App Theme

/// Controls the app's color scheme preference.
enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    /// Human-readable display name for the theme.
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// SF Symbol name representing this theme.
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// The corresponding SwiftUI `ColorScheme`, or `nil` for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Accent Color Choice

/// User-selectable accent color for the app UI.
enum AccentColorChoice: String, Codable, Sendable, CaseIterable {
    case system
    case blue
    case purple
    case cyan
    case green
    case orange
    case pink
    case red

    /// Human-readable display name for the accent color.
    var displayName: String {
        switch self {
        case .system: return "System"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .cyan: return "Cyan"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .red: return "Red"
        }
    }

    /// The corresponding SwiftUI `Color`, or `nil` for system default.
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .cyan: return .cyan
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .red: return .red
        }
    }
}

// MARK: - Waveform Style

/// Visual style for the voice waveform animation.
enum WaveformStyle: String, Codable, Sendable, CaseIterable {
    /// Gentle sine wave animation.
    case subtle
    /// Dynamic bar visualization that responds to audio levels.
    case expressive
    /// Simple dot pulse — minimal and clean.
    case minimal

    /// Human-readable display name for the waveform style.
    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .expressive: return "Expressive"
        case .minimal: return "Minimal"
        }
    }

    /// Description of what the style looks like.
    var description: String {
        switch self {
        case .subtle: return "Gentle sine wave"
        case .expressive: return "Dynamic bars"
        case .minimal: return "Simple dot pulse"
        }
    }
}
