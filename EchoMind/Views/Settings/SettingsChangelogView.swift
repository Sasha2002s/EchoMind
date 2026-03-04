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
                Section("March 4, 2026") {
                    Label("Hardened recording start flow to prevent rapid-tap/Siri race conditions", systemImage: "lock.shield")
                    Label("Refined Local Whisper action buttons and fixed stretched Delete button rendering", systemImage: "trash.slash")
                }

                Section("March 1, 2026 (Today)") {
                    Label("Added dependency container and root-level injection", systemImage: "shippingbox")
                    Label("Unified recordings access with one repository", systemImage: "externaldrive.connected.to.line.below")
                    Label("Split Settings into focused section files", systemImage: "square.split.2x2")
                    Label("Added Voice Memo import directly into Library", systemImage: "waveform.badge.plus")
                    Label("Enabled haptics setting and wired feedback across major actions", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Made Theme setting functional (system/light/dark)", systemImage: "circle.lefthalf.filled")
                    Label("Added Storage Usage screen with category graph + model breakdown", systemImage: "chart.bar.xaxis")
                    Label("Added background Whisper model download with resume/cancel handling", systemImage: "arrow.down.circle")
                    Label("Fixed Whisper Large model URL resolution/install flow + checksum verification", systemImage: "checkmark.shield")
                    Label("Hid unavailable Whisper Large in engine picker and cleaned Download/Delete visibility", systemImage: "line.3.horizontal.decrease.circle")
                    Label("Added default transcription/AI settings and auto-transcription after recording", systemImage: "slider.horizontal.3")
                    Label("Added background transcription queue for longer recordings", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Label("Improved Recording Detail UX and playback scrubbing behavior", systemImage: "waveform.path.ecg")
                    Label("Added chunked on-device summarization for long transcripts", systemImage: "text.badge.checkmark")
                    Label("Added lyrics/famous phrase detection and smarter title renaming", systemImage: "music.note")
                    Label("Added Library row context menu + tappable Home recents + recording pause", systemImage: "hand.tap")
                    Label("Added transcription translation action and transcription word counter", systemImage: "character.bubble")
                    Label("Fixed imported audio visibility in Library refresh/loading flow", systemImage: "books.vertical")
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
