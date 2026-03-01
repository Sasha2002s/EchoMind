//
//  SummaryTranslationViewModel.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import SwiftUI
import Combine
#if canImport(Translation)
import Translation
#endif

@MainActor
final class SummaryTranslationViewModel: ObservableObject {
    @Published var translatedSummaryText: String = ""
    @Published var isTranslating: Bool = false
    @Published var translationError: String? = nil
    @Published var selectedLocale: SpeechLocaleOption = .system {
        didSet {
            loadTranslatedSummaryIfExists()
        }
    }
#if canImport(Translation)
    @Published var translationConfiguration: TranslationSession.Configuration? = nil
#endif

    private var audioURL: URL
    private var lastSummaryText: String = ""
    private let fileService: RecordingDetailFileService

    init(audioURL: URL, fileService: RecordingDetailFileService? = nil) {
        self.audioURL = audioURL
        self.fileService = fileService ?? RecordingDetailFileService()
        loadTranslatedSummaryIfExists()
    }

    func syncAudioURL(_ newAudioURL: URL) {
        guard newAudioURL != audioURL else { return }
        audioURL = newAudioURL
        loadTranslatedSummaryIfExists()
    }

    func handleSummaryChange(_ summaryText: String) {
        let trimmed = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastSummaryText else { return }

        // Why: avoid showing stale translation when summary content changes.
        lastSummaryText = trimmed
        translatedSummaryText = ""
        translationError = nil
    }

    func translate(summaryText: String) async {
        guard !isTranslating else { return }

        translationError = nil
        isTranslating = true

        let text = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translationError = "Summarize first, then translate."
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
            translatedSummaryText = translated
            try fileService.saveTranslatedSummary(translated, for: audioURL, locale: selectedLocale)
        } catch {
            translationError = error.localizedDescription
        }
#endif
    }

#if canImport(Translation)
    func performFrameworkTranslation(using session: TranslationSession, summaryText: String) async {
        do {
            let response = try await session.translate(summaryText)
            let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty {
                translationError = "Translation returned empty text."
            } else {
                translatedSummaryText = out
                try? fileService.saveTranslatedSummary(out, for: audioURL, locale: selectedLocale)
            }
        } catch {
            translationError = "Translation failed: \(error.localizedDescription)"
        }

        translationConfiguration = nil
        isTranslating = false
    }
#endif

    private func loadTranslatedSummaryIfExists() {
        translatedSummaryText = fileService.loadTranslatedSummaryIfPresent(
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
