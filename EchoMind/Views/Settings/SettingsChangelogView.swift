//
//  SettingsChangelogView.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("March 1, 2026 (Today)") {
                    Label("Added dependency container and root-level injection", systemImage: "shippingbox")
                    Label("Unified recordings access with one repository", systemImage: "externaldrive.connected.to.line.below")
                    Label("Split Settings into focused section files", systemImage: "square.split.2x2")
                    Label("Added Voice Memo import directly into Library", systemImage: "waveform.badge.plus")
                    Label("Enabled haptics setting and wired feedback across major actions", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Made Theme setting functional (system/light/dark)", systemImage: "circle.lefthalf.filled")
                    Label("Added Storage Usage screen with category graph + model breakdown", systemImage: "chart.bar.xaxis")
                }

                Section("February 28, 2026 (Yesterday)") {
                    Label("Moved backend logic out of key views into services/view models", systemImage: "arrow.triangle.branch")
                    Label("Moved summary translation flow into dedicated Translation module", systemImage: "character.bubble")
                    Label("Hardened recording deletion error handling", systemImage: "trash.slash")
                    Label("Added Whisper model checksum verification during download", systemImage: "checkmark.shield")
                    Label("Fixed player completion state handling in library audio player", systemImage: "play.circle")
                }
            }
            .navigationTitle("Changelog")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
