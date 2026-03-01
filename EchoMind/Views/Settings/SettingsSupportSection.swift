//
//  SettingsSupportSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsSupportSection: View {
    var body: some View {
        Section("Support") {
            SettingsRow(
                title: "Send Feedback",
                subtitle: "Email us your thoughts",
                systemImage: "envelope"
            )

            SettingsRow(
                title: "Privacy Policy",
                subtitle: "Read before using",
                systemImage: "hand.raised"
            )

            SettingsRow(
                title: "Terms of Use",
                subtitle: "App rules and licensing",
                systemImage: "doc.text"
            )
        }
    }
}

