//
//  RecordingDetailViewModel.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class RecordingDetailViewModel: ObservableObject {
    let item: RecordingFile

    @Published var showDeleteConfirm: Bool = false
    @Published var deleteError: String? = nil
    @Published var didDeleteRecording: Bool = false

    @Published var transcriptText: String = ""
    @Published var currentAudioURL: URL
    @Published var isTranscriptHidden: Bool = false
    @Published var summaryText: String = ""
    @Published var isSummaryHidden: Bool = false
    @Published var isSummarizing: Bool = false
    @Published var summaryError: String? = nil

    @Published var isLoadingTranscript: Bool = false
    @Published var transcriptionError: String? = nil
    @Published var isTranscribing: Bool = false
    @Published var whisperStatus: String? = nil

    @Published var selectedEngine: TranscriptionEngine = .whisper
    @Published var selectedSpeechLocale: SpeechLocaleOption = .system
    @Published var selectedWhisperLocale: SpeechLocaleOption = .system
    @Published var selectedWhisperModel: WhisperModelOption = .base

    private let player: LibraryAudioPlayer
    private let fileService: RecordingDetailFileService
    private let appleTranscriber: AppleSpeechFileTranscriber
    private let whisperTranscriber: WhisperFileTranscriber

    init(
        item: RecordingFile,
        player: LibraryAudioPlayer,
        fileService: RecordingDetailFileService? = nil,
        appleTranscriber: AppleSpeechFileTranscriber? = nil,
        whisperTranscriber: WhisperFileTranscriber? = nil
    ) {
        self.item = item
        self.player = player
        self.fileService = fileService ?? RecordingDetailFileService()
        self.appleTranscriber = appleTranscriber ?? AppleSpeechFileTranscriber()
        self.whisperTranscriber = whisperTranscriber ?? WhisperFileTranscriber()
        self.currentAudioURL = item.url
    }

    var displayTitleForCurrentFile: String {
        let base = currentAudioURL.deletingPathExtension().lastPathComponent
        if base.lowercased().hasPrefix("recording_") {
            return "Recording \(item.createdAtFormatted)"
        }
        return base
    }

    func onAppear() {
        loadTranscriptAndSummary()
    }

    func onDisappear() {
        if player.isPlaying(id: item.id) {
            player.stop()
        }
    }

    func deleteRecording() async {
        if player.isPlaying(id: item.id) {
            player.stop()
        }

        do {
            try fileService.deleteRecordingBundle(audioURL: currentAudioURL, locales: SpeechLocaleOption.allCases)
            didDeleteRecording = true
        } catch {
            deleteError = error.localizedDescription
        }
    }

    func transcribe() async {
        switch selectedEngine {
        case .appleSpeech:
            await transcribeWithAppleSpeech()
        case .whisper:
            await transcribeWithWhisper()
        }
    }

    func summarizeOnDevice() async {
        guard !isSummarizing else { return }

        summaryError = nil
        isSummarizing = true
        defer { isSummarizing = false }

        let text = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            summaryError = "Transcribe first, then summarize."
            return
        }

        do {
            async let summaryTask = OnDeviceAIService.summarize(text)
            async let titleTask = OnDeviceAIService.suggestTitle(text)

            let summary = try await summaryTask
            let suggestedTitle = try await titleTask

            summaryText = summary
            try fileService.saveSummary(summary, for: currentAudioURL)

            if player.isPlaying(id: item.id) {
                player.stop()
            }

            currentAudioURL = try fileService.renameRecordingAndSidecars(
                audioURL: currentAudioURL,
                newName: suggestedTitle,
                locales: SpeechLocaleOption.allCases
            )
        } catch {
            summaryError = error.localizedDescription
        }
    }

    private func loadTranscriptAndSummary() {
        isLoadingTranscript = true
        transcriptionError = nil
        summaryError = nil
        defer { isLoadingTranscript = false }

        let loaded = fileService.loadTranscriptAndSummary(for: currentAudioURL)
        transcriptText = loaded.transcript
        summaryText = loaded.summary
    }

    private func transcribeWithWhisper() async {
        guard !isTranscribing else { return }

        transcriptionError = nil
        summaryError = nil
        summaryText = ""
        whisperStatus = "Preparing \(selectedWhisperLocale.shortTitle)..."
        isTranscribing = true
        defer {
            isTranscribing = false
            whisperStatus = nil
        }

        guard FileManager.default.fileExists(atPath: currentAudioURL.path) else {
            transcriptionError = "Audio file not found."
            return
        }

        do {
            whisperStatus = "Transcribing (\(selectedWhisperLocale.shortTitle))..."

            let result = try await withTimeout(seconds: 120) {
                try await self.whisperTranscriber.transcribeFile(
                    url: self.currentAudioURL,
                    model: self.selectedWhisperModel,
                    languageCode: self.selectedWhisperLocale.languageCode
                )
            }

            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                transcriptionError = "Transcription returned empty text."
                return
            }

            transcriptText = cleaned
            try fileService.saveTranscript(cleaned, for: currentAudioURL)
        } catch {
            if (error as NSError).domain == "Timeout" {
                transcriptionError = "Whisper is taking too long (model download/first setup can take minutes). Try a smaller model first (tiny/base), keep the app open on Wi-Fi, then retry large-v3."
            } else {
                transcriptionError = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func transcribeWithAppleSpeech() async {
        guard !isTranscribing else { return }

        transcriptionError = nil
        summaryError = nil
        summaryText = ""
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            try await AppleSpeechFileTranscriber.ensureAuthorized()
        } catch {
            transcriptionError = error.localizedDescription
            return
        }

        guard FileManager.default.fileExists(atPath: currentAudioURL.path) else {
            transcriptionError = "Audio file not found."
            return
        }

        do {
            let locale = selectedSpeechLocale.locale
            let result = try await appleTranscriber.transcribeFile(url: currentAudioURL, locale: locale)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.isEmpty {
                transcriptionError = "Transcription returned empty text."
                return
            }

            transcriptText = cleaned
            try fileService.saveTranscript(cleaned, for: currentAudioURL)
        } catch {
            transcriptionError = "Transcription failed: \(error.localizedDescription)"
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "Timeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out after \(seconds)s"])
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}
