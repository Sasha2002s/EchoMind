//
//  HapticsService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import UIKit

enum HapticsService {
    private static let hapticsSettingKey = "settings.haptics"

    private static var isEnabled: Bool {
        // Why: keep current behavior as "on by default" until user explicitly changes the setting.
        if UserDefaults.standard.object(forKey: hapticsSettingKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: hapticsSettingKey)
    }

    static func selectionChanged() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

