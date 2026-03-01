//
//  SettingsRecordingSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI
import UIKit

struct SettingsRecordingSection: View {
    @Environment(\.openURL) private var openURL
    @Binding var defaultTranscriptionModel: TranscriptionEngine
    @Binding var transcriptionLanguage: TranscriptionLanguage
    @Binding var preventAutoLock: Bool

    var body: some View {
        Section("Recording") {
            ToggleRow(
                title: "Prevent Auto-Lock",
                subtitle: "Keep screen awake while recording",
                systemImage: "lock.open",
                isOn: $preventAutoLock
            )

            Button {
                HapticsService.selectionChanged()
                openAppSettings()
            } label: {
                SettingsRow(
                    title: "Background App Refresh",
                    subtitle: backgroundRefreshStatusText,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            PickerRow(
                title: "Default Transcription Model",
                subtitle: defaultTranscriptionModel.title,
                systemImage: "waveform.badge.mic",
                selection: $defaultTranscriptionModel
            ) {
                Text("Apple").tag(TranscriptionEngine.appleSpeech)
                Text("Whisper Basic").tag(TranscriptionEngine.whisperBasic)
                Text("Whisper Large v3").tag(TranscriptionEngine.whisperLarge)
            }

            PickerRow(
                title: "Transcription Language",
                subtitle: transcriptionLanguage.displayName,
                systemImage: "globe",
                selection: $transcriptionLanguage
            ) {
                ForEach(TranscriptionLanguage.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
        }
    }

    private var backgroundRefreshStatusText: String {
        let state: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            state = "On"
        case .denied:
            state = "Off"
        case .restricted:
            state = "Restricted"
        @unknown default:
            state = "Unknown"
        }
        return "\(state) • Tap to open iOS Settings"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
