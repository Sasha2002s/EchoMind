//
//  SettingsAppearanceSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsAppearanceSection: View {
    @Binding var theme: AppTheme
    @Binding var hapticsEnabled: Bool
    @Binding var soundsEnabled: Bool

    var body: some View {
        Section("Appearance") {
            PickerRow(
                title: "Theme",
                subtitle: theme.displayName,
                systemImage: "circle.lefthalf.filled",
                selection: $theme
            ) {
                ForEach(AppTheme.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }

            ToggleRow(
                title: "Haptics",
                subtitle: "Vibration feedback",
                systemImage: "hand.tap",
                isOn: $hapticsEnabled
            )

            ToggleRow(
                title: "Sounds",
                subtitle: "Start/stop sounds",
                systemImage: "speaker.wave.2",
                isOn: $soundsEnabled
            )
        }
    }
}

