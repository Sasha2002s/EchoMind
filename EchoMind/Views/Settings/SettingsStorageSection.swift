//
//  SettingsStorageSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsStorageSection: View {
    @Binding var keepAudio: KeepAudioPolicy

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

            NavigationLink {
                StorageUsageView()
            } label: {
                SettingsRow(
                    title: "Storage Usage",
                    subtitle: "Audio, text, and model size",
                    systemImage: "chart.pie"
                )
            }
            .simultaneousGesture(TapGesture().onEnded {
                HapticsService.selectionChanged()
            })
        }
    }
}
