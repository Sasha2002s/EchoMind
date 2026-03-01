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

    @AppStorage("settings.defaultTranscriptionModel") private var defaultTranscriptionModel: TranscriptionEngine = .appleSpeech
    @AppStorage("settings.transcriptionLanguage") private var transcriptionLanguage: TranscriptionLanguage = .auto
    @AppStorage("settings.defaultAIModel") private var defaultAIModel: DefaultAIModel = .apple
    @AppStorage("settings.summaryStyle") private var summaryStyle: SummaryStyle = .balanced
    @AppStorage("settings.taskDetection") private var taskDetectionEnabled: Bool = true

    @AppStorage("settings.keepAudio") private var keepAudio: KeepAudioPolicy = .always
    @AppStorage("settings.defaultExportFormat") private var defaultExportFormat: ExportFormatPreference = .m4a
    @AppStorage("settings.shareStyle") private var shareStyle: ShareStylePreference = .audioOnly
    @AppStorage("settings.preventAutoLock") private var preventAutoLock: Bool = true
    @AppStorage("settings.whisperModel") private var whisperModel: WhisperModelChoice = .none
    @AppStorage(WhisperBackgroundDownloadManager.wifiOnlySettingKey) private var whisperDownloadWiFiOnly = true
    @AppStorage(WhisperBackgroundDownloadManager.pauseOnLowPowerSettingKey) private var whisperPauseOnLowPower = true

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
                    defaultTranscriptionModel: $defaultTranscriptionModel,
                    transcriptionLanguage: $transcriptionLanguage,
                    preventAutoLock: $preventAutoLock
                )

                SettingsAISection(
                    defaultAIModel: $defaultAIModel,
                    summaryStyle: $summaryStyle,
                    taskDetectionEnabled: $taskDetectionEnabled
                )

                SettingsWhisperSection(
                    whisperModel: $whisperModel,
                    downloadOnWiFiOnly: $whisperDownloadWiFiOnly,
                    pauseOnLowPowerMode: $whisperPauseOnLowPower,
                    vm: vm
                )

                SettingsStorageSection(
                    keepAudio: $keepAudio,
                    defaultExportFormat: $defaultExportFormat,
                    shareStyle: $shareStyle
                )

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
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(
        viewModel: SettingsViewModel(
            whisperModelManager: WhisperModelManager(),
            whisperBackgroundDownloadManager: WhisperBackgroundDownloadManager.shared
        )
    )
}
