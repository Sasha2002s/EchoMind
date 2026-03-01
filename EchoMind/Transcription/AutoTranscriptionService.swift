//
//  AutoTranscriptionService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AutoTranscriptionService: ObservableObject {
    @AppStorage("settings.defaultTranscriptionModel") private var defaultTranscriptionModel: TranscriptionEngine = .appleSpeech
    @AppStorage("settings.transcriptionLanguage") private var transcriptionLanguage: TranscriptionLanguage = .auto
    private let fileService: RecordingDetailFileService
    private let backgroundTranscriptionManager: BackgroundTranscriptionManager

    init(
        fileService: RecordingDetailFileService,
        backgroundTranscriptionManager: BackgroundTranscriptionManager
    ) {
        self.fileService = fileService
        self.backgroundTranscriptionManager = backgroundTranscriptionManager
    }

    convenience init() {
        self.init(
            fileService: RecordingDetailFileService(),
            backgroundTranscriptionManager: BackgroundTranscriptionManager.shared
        )
    }

    func transcribeIfNeeded(audioURL: URL) async {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        let existing = fileService.loadTranscriptAndSummary(for: audioURL).transcript
        guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        await backgroundTranscriptionManager.enqueueTranscription(
            audioURL: audioURL,
            engine: defaultTranscriptionModel,
            language: transcriptionLanguage
        )
        // Why: process at least one chunk immediately when app is still foregrounded.
        await backgroundTranscriptionManager.processPendingJobsNow(maxChunks: 1)
        BackgroundTranscriptionManager.scheduleBackgroundProcessing()
    }

    func processQueuedTranscriptionsInForeground() async {
        await backgroundTranscriptionManager.processPendingJobsNow(maxChunks: 2)
    }
}
