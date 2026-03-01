//
//  SettingsEnums.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto
    case en
    case de
    case uk
    case ru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "English"
        case .de: return "German"
        case .uk: return "Ukrainian"
        case .ru: return "Russian"
        }
    }
}

enum SummaryStyle: String, CaseIterable, Identifiable {
    case short
    case balanced
    case detailed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .balanced: return "Balanced"
        case .detailed: return "Detailed"
        }
    }
}

enum KeepAudioPolicy: String, CaseIterable, Identifiable {
    case always
    case days7
    case days30
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .days7: return "7 days"
        case .days30: return "30 days"
        case .never: return "Never"
        }
    }
}

