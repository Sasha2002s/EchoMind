//
//  SettingsView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.theme") private var theme: AppTheme = .system
    @AppStorage("settings.haptics") private var hapticsEnabled: Bool = true
    @AppStorage("settings.sounds") private var soundsEnabled: Bool = false

    @AppStorage("settings.transcriptionLanguage") private var transcriptionLanguage: TranscriptionLanguage = .auto
    @AppStorage("settings.summaryStyle") private var summaryStyle: SummaryStyle = .balanced
    @AppStorage("settings.taskDetection") private var taskDetectionEnabled: Bool = true

    @AppStorage("settings.keepAudio") private var keepAudio: KeepAudioPolicy = .always
    @AppStorage("settings.preventAutoLock") private var preventAutoLock: Bool = true
    @AppStorage("settings.whisperModel") private var whisperModel: WhisperModelChoice = .none

    @StateObject private var vm: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        // Why: the app root can inject a preconfigured view model when needed.
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                SettingsAppearanceSection(
                    theme: $theme,
                    hapticsEnabled: $hapticsEnabled,
                    soundsEnabled: $soundsEnabled
                )

                SettingsRecordingSection(
                    transcriptionLanguage: $transcriptionLanguage,
                    preventAutoLock: $preventAutoLock
                )

                SettingsAISection(
                    summaryStyle: $summaryStyle,
                    taskDetectionEnabled: $taskDetectionEnabled
                )

                SettingsWhisperSection(whisperModel: $whisperModel, vm: vm)

                SettingsStorageSection(keepAudio: $keepAudio)

                SettingsSupportSection()
                SettingsChangelogSection()
                SettingsFooterSection()
            }
            .onAppear {
                vm.refreshWhisperModelInstalledState(for: whisperModel)
            }
            .onChange(of: whisperModel) { _, newValue in
                vm.refreshWhisperModelInstalledState(for: newValue)
            }
            .onDisappear {
                vm.cancelWhisperDownload()
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(whisperModelManager: WhisperModelManager()))
}
