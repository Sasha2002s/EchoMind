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
    @AppStorage("settings.whisperModel") private var settingsWhisperModel: WhisperModelChoice = .none

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

    @AppStorage("settings.defaultTranscriptionModel") private var defaultTranscriptionModel: TranscriptionEngine = .appleSpeech
    @Published var selectedEngine: TranscriptionEngine = .appleSpeech
    @Published var selectedSpeechLocale: SpeechLocaleOption = .system
    @Published var selectedWhisperLocale: SpeechLocaleOption = .system
    @Published var isWhisperLargeAvailable: Bool = false

    private let player: LibraryAudioPlayer
    private let fileService: RecordingDetailFileService
    private let appleTranscriber: AppleSpeechFileTranscriber
    private let whisperTranscriber: WhisperFileTranscriber
    private let whisperModelManager: WhisperModelManager

    var availableEngines: [TranscriptionEngine] {
        var engines: [TranscriptionEngine] = [.whisperBasic]
        if isWhisperLargeAvailable {
            engines.append(.whisperLarge)
        }
        engines.append(.appleSpeech)
        return engines
    }

    init(
        item: RecordingFile,
        player: LibraryAudioPlayer,
        fileService: RecordingDetailFileService? = nil,
        appleTranscriber: AppleSpeechFileTranscriber? = nil,
        whisperTranscriber: WhisperFileTranscriber? = nil,
        whisperModelManager: WhisperModelManager? = nil
    ) {
        self.item = item
        self.player = player
        self.fileService = fileService ?? RecordingDetailFileService()
        self.appleTranscriber = appleTranscriber ?? AppleSpeechFileTranscriber()
        self.whisperTranscriber = whisperTranscriber ?? WhisperFileTranscriber()
        self.whisperModelManager = whisperModelManager ?? WhisperModelManager()
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
        refreshWhisperLargeAvailability()
        selectedEngine = defaultTranscriptionModel
        if selectedEngine == .whisperLarge && !isWhisperLargeAvailable {
            // Why: avoid preselecting an engine the user cannot run yet.
            selectedEngine = .whisperBasic
        }
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
        refreshWhisperLargeAvailability()
        if selectedEngine == .whisperLarge && !isWhisperLargeAvailable {
            transcriptionError = "Whisper Large is not downloaded yet."
            // Why: keep the picker in a valid state after blocking unavailable large model usage.
            selectedEngine = .whisperBasic
            return
        }

        switch selectedEngine {
        case .appleSpeech:
            await transcribeWithAppleSpeech()
        case .whisperBasic:
            await transcribeWithWhisper(model: .base, preferLocalModel: false)
        case .whisperLarge:
            await transcribeWithWhisper(model: .largeV3, preferLocalModel: true)
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
            let baseSummary = try await OnDeviceAIService.summarize(text)
            // Why: title/reference enrich output but should never block successful summary generation.
            let suggestedTitle = (try? await OnDeviceAIService.suggestTitle(text)) ?? "Recording \(item.createdAtFormatted)"
            let referenceResult = (try? await OnDeviceAIService.checkForFamousReference(text))
                ?? OnDeviceAIService.ReferenceCheckResult(noteForSummary: nil, suggestedSongTitle: nil)

            let summary: String
            if let note = referenceResult.noteForSummary, !note.isEmpty {
                summary = "\(baseSummary)\n\nReference note: \(note)"
            } else {
                summary = baseSummary
            }

            summaryText = summary
            try fileService.saveSummary(summary, for: currentAudioURL)

            if player.isPlaying(id: item.id) {
                player.stop()
            }

            let preferredTitle = referenceResult.suggestedSongTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let renameTitle = (preferredTitle?.isEmpty == false) ? preferredTitle! : suggestedTitle

            currentAudioURL = try fileService.renameRecordingAndSidecars(
                audioURL: currentAudioURL,
                newName: renameTitle,
                locales: SpeechLocaleOption.allCases
            )
        } catch {
            summaryError = error.localizedDescription
        }
    }

    private func refreshWhisperLargeAvailability() {
        // Why: picker options should reflect real model installation state.
        isWhisperLargeAvailable = whisperModelManager.isModelInstalled(for: .largeV3_547)
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

    private func transcribeWithWhisper(model: WhisperModelOption, preferLocalModel: Bool) async {
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
            let localModelFolderPath = preferLocalModel
                ? whisperModelManager.installedModelFolderPath(for: settingsWhisperModel)
                : nil
            if localModelFolderPath != nil {
                whisperStatus = "Transcribing (\(selectedWhisperLocale.shortTitle), local model)..."
            } else {
                whisperStatus = "Transcribing (\(selectedWhisperLocale.shortTitle))..."
            }

            let result = try await withTimeout(seconds: 120) {
                try await self.whisperTranscriber.transcribeFile(
                    url: self.currentAudioURL,
                    model: model,
                    languageCode: self.selectedWhisperLocale.languageCode,
                    localModelFolderPath: localModelFolderPath
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
