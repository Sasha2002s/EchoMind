//
//  AppDependencies.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import Combine

final class AppDependencies: ObservableObject {
    let recordingRepository: any RecordingRepository
    let voiceMemoImportService: any VoiceMemoImporting
    let libraryAudioPlayer: LibraryAudioPlayer
    let settingsViewModel: SettingsViewModel

    init(
        recordingRepository: any RecordingRepository,
        voiceMemoImportService: any VoiceMemoImporting,
        libraryAudioPlayer: LibraryAudioPlayer,
        settingsViewModel: SettingsViewModel
    ) {
        self.recordingRepository = recordingRepository
        self.voiceMemoImportService = voiceMemoImportService
        self.libraryAudioPlayer = libraryAudioPlayer
        self.settingsViewModel = settingsViewModel
    }

    static func live() -> AppDependencies {
        // Why: centralize app wiring in one place instead of constructing services in views.
        let whisperModelManager = WhisperModelManager()
        let whisperBackgroundDownloadManager = WhisperBackgroundDownloadManager.shared
        return AppDependencies(
            recordingRepository: FileSystemRecordingRepository(),
            voiceMemoImportService: VoiceMemoImportService(),
            libraryAudioPlayer: LibraryAudioPlayer(),
            settingsViewModel: SettingsViewModel(
                whisperModelManager: whisperModelManager,
                whisperBackgroundDownloadManager: whisperBackgroundDownloadManager
            )
        )
    }

    static func preview() -> AppDependencies {
        let whisperModelManager = WhisperModelManager()
        return AppDependencies(
            recordingRepository: PreviewRecordingRepository(),
            voiceMemoImportService: VoiceMemoImportService(),
            libraryAudioPlayer: LibraryAudioPlayer(),
            settingsViewModel: SettingsViewModel(
                whisperModelManager: whisperModelManager,
                whisperBackgroundDownloadManager: WhisperBackgroundDownloadManager.shared
            )
        )
    }
}

#if DEBUG
private struct PreviewRecordingRepository: RecordingRepository {
    func loadAllRecordings() async -> [RecordingFile] {
        [sampleRecording(offset: -900), sampleRecording(offset: -3_600)]
    }

    func loadRecentRecordings(limit: Int) async -> [RecordingFile] {
        let all = await loadAllRecordings()
        return Array(all.prefix(max(0, limit)))
    }

    private func sampleRecording(offset: TimeInterval) -> RecordingFile {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview_\(Int(abs(offset))).m4a")
        return RecordingFile(
            id: url.lastPathComponent,
            url: url,
            createdAt: Date().addingTimeInterval(offset),
            duration: 73
        )
    }
}
#endif
