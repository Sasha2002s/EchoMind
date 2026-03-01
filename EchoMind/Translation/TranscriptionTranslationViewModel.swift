//
//  TranscriptionTranslationViewModel.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import SwiftUI
import Combine
#if canImport(Translation)
import Translation
#endif

@MainActor
final class TranscriptionTranslationViewModel: ObservableObject {
    @Published var translatedTranscriptText: String = ""
    @Published var isTranslating: Bool = false
    @Published var translationError: String? = nil
    @Published var selectedLocale: SpeechLocaleOption = .system {
        didSet {
            loadTranslatedTranscriptIfExists()
        }
    }
#if canImport(Translation)
    @Published var translationConfiguration: TranslationSession.Configuration? = nil
#endif

    private var audioURL: URL
    private var lastTranscriptText: String = ""
    private let fileService: RecordingDetailFileService

    init(audioURL: URL, fileService: RecordingDetailFileService? = nil) {
        self.audioURL = audioURL
        self.fileService = fileService ?? RecordingDetailFileService()
        let storedTranscript = self.fileService
            .loadTranscriptAndSummary(for: audioURL)
            .transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastTranscriptText = storedTranscript
        loadTranslatedTranscriptIfExists()
    }

    func syncAudioURL(_ newAudioURL: URL) {
        guard newAudioURL != audioURL else { return }
        audioURL = newAudioURL
        let storedTranscript = fileService
            .loadTranscriptAndSummary(for: newAudioURL)
            .transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscriptText = storedTranscript
        loadTranslatedTranscriptIfExists()
    }

    func handleTranscriptChange(_ transcriptText: String) {
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastTranscriptText else { return }

        // Why: avoid showing stale translation when transcript content changes.
        lastTranscriptText = trimmed
        translatedTranscriptText = ""
        translationError = nil
    }

    func translate(transcriptText: String) async {
        guard !isTranslating else { return }

        translationError = nil
        isTranslating = true

        let text = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translationError = "Transcribe first, then translate."
            isTranslating = false
            return
        }

#if canImport(Translation)
        translationConfiguration = TranslationSession.Configuration(
            source: nil,
            target: targetLanguageForTranslationFramework()
        )
        return
#else
        defer { isTranslating = false }

        do {
            let translated = try await OnDeviceAIService.translateWithFoundationModels(
                text: text,
                targetLanguageDisplayName: selectedLocale.title
            )
            translatedTranscriptText = translated
            try fileService.saveTranslatedTranscript(translated, for: audioURL, locale: selectedLocale)
        } catch {
            translationError = error.localizedDescription
        }
#endif
    }

#if canImport(Translation)
    func performFrameworkTranslation(using session: TranslationSession, transcriptText: String) async {
        do {
            let response = try await session.translate(transcriptText)
            let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty {
                translationError = "Translation returned empty text."
            } else {
                translatedTranscriptText = out
                try? fileService.saveTranslatedTranscript(out, for: audioURL, locale: selectedLocale)
            }
        } catch {
            translationError = "Translation failed: \(error.localizedDescription)"
        }

        translationConfiguration = nil
        isTranslating = false
    }
#endif

    private func loadTranslatedTranscriptIfExists() {
        translatedTranscriptText = fileService.loadTranslatedTranscriptIfPresent(
            for: audioURL,
            locale: selectedLocale
        )
    }

#if canImport(Translation)
    private func targetLanguageForTranslationFramework() -> Locale.Language {
        if let code = selectedLocale.languageCode, !code.isEmpty {
            return Locale.Language(identifier: code)
        }

        let deviceCode = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: deviceCode)
    }
#endif
}
