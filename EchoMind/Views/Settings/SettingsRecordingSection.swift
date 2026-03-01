//
//  SettingsRecordingSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsRecordingSection: View {
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
}

