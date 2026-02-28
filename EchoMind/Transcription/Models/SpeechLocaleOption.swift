//
//  SpeechLocaleOption.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Foundation

// MARK: - Speech locale option

enum SpeechLocaleOption: String, CaseIterable, Identifiable, Hashable {
    case system
    case enUS
    case deDE
    case ukUA
    case ruRU

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System language"
        case .enUS: return "English (US)"
        case .deDE: return "German (DE)"
        case .ukUA: return "Ukrainian (UA)"
        case .ruRU: return "Russian (RU)"
        }
    }

    var shortTitle: String {
        switch self {
        case .system: return "System"
        case .enUS: return "EN"
        case .deDE: return "DE"
        case .ukUA: return "UK"
        case .ruRU: return "RU"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return Locale.current
        case .enUS:
            return Locale(identifier: "en-US")
        case .deDE:
            return Locale(identifier: "de-DE")
        case .ukUA:
            return Locale(identifier: "uk-UA")
        case .ruRU:
            return Locale(identifier: "ru-RU")
        }
    }
    var languageCode: String? {
        switch self {
        case .system:
            return Locale.current.language.languageCode?.identifier
        case .enUS:
            return "en"
        case .deDE:
            return "de"
        case .ukUA:
            return "uk"
        case .ruRU:
            return "ru"
        }
    }
}


