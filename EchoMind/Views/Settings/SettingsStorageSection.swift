//
//  SettingsStorageSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsStorageSection: View {
    @Binding var keepAudio: KeepAudioPolicy
    @Binding var defaultExportFormat: ExportFormatPreference
    @Binding var shareStyle: ShareStylePreference

    var body: some View {
        Section("Storage") {
            PickerRow(
                title: "Keep Audio",
                subtitle: keepAudio.displayName,
                systemImage: "externaldrive",
                selection: $keepAudio
            ) {
                ForEach(KeepAudioPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            PickerRow(
                title: "Default Export Format",
                subtitle: defaultExportFormat.displayName,
                systemImage: "square.and.arrow.down",
                selection: $defaultExportFormat
            ) {
                ForEach(ExportFormatPreference.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            PickerRow(
                title: "Share Style",
                subtitle: shareStyle.displayName,
                systemImage: "square.and.arrow.up",
                selection: $shareStyle
            ) {
                ForEach(ShareStylePreference.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            NavigationLink {
                StorageUsageView()
            } label: {
                SettingsRow(
                    title: "Storage Usage",
                    subtitle: "Audio, text, and model size",
                    systemImage: "chart.pie"
                )
                // Why: custom row labels can otherwise only register taps on visible content.
                .contentShape(Rectangle())
            }
        }
    }
}
