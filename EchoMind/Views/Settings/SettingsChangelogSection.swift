//
//  SettingsChangelogSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsChangelogSection: View {
    @State private var showChangelog = false

    var body: some View {
        Section("Changelog") {
            Button {
                HapticsService.impact(.light)
                showChangelog = true
            } label: {
                SettingsRow(
                    title: "What’s New",
                    subtitle: "See recent changes",
                    systemImage: "sparkles"
                )
                // Why: keep the whole row tappable even with plain button styling.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView()
        }
    }
}
