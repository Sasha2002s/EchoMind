//
//  RecordingDetailFileService.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation

struct RecordingDetailFileService {
    private let fileManager: FileManager = .default
    nonisolated init() {}

    nonisolated func sidecarTranscriptURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("txt")
    }

    nonisolated func sidecarSummaryURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("summary.txt")
    }

    func sidecarTranslatedTranscriptURL(for audioURL: URL, locale: SpeechLocaleOption) -> URL {
        let code = locale.languageCode ?? "system"
        return audioURL.deletingPathExtension().appendingPathExtension("transcript.\(code).txt")
    }

    func sidecarTranslatedSummaryURL(for audioURL: URL, locale: SpeechLocaleOption) -> URL {
        let code = locale.languageCode ?? "system"
        return audioURL.deletingPathExtension().appendingPathExtension("summary.\(code).txt")
    }

    nonisolated func loadTranscriptAndSummary(for audioURL: URL) -> (transcript: String, summary: String) {
        let transcript = loadTextIfPresent(from: sidecarTranscriptURL(for: audioURL))
        let summary = loadTextIfPresent(from: sidecarSummaryURL(for: audioURL))
        return (transcript, summary)
    }

    func loadTranslatedSummaryIfPresent(for audioURL: URL, locale: SpeechLocaleOption) -> String {
        let url = sidecarTranslatedSummaryURL(for: audioURL, locale: locale)
        return loadTextIfPresent(from: url)
    }

    func loadTranslatedTranscriptIfPresent(for audioURL: URL, locale: SpeechLocaleOption) -> String {
        let url = sidecarTranslatedTranscriptURL(for: audioURL, locale: locale)
        return loadTextIfPresent(from: url)
    }

    nonisolated func saveTranscript(_ text: String, for audioURL: URL) throws {
        try Data(text.utf8).write(to: sidecarTranscriptURL(for: audioURL), options: [.atomic])
    }

    func saveSummary(_ text: String, for audioURL: URL) throws {
        try Data(text.utf8).write(to: sidecarSummaryURL(for: audioURL), options: [.atomic])
    }

    func saveTranslatedTranscript(_ text: String, for audioURL: URL, locale: SpeechLocaleOption) throws {
        try Data(text.utf8).write(to: sidecarTranslatedTranscriptURL(for: audioURL, locale: locale), options: [.atomic])
    }

    func saveTranslatedSummary(_ text: String, for audioURL: URL, locale: SpeechLocaleOption) throws {
        try Data(text.utf8).write(to: sidecarTranslatedSummaryURL(for: audioURL, locale: locale), options: [.atomic])
    }

    func deleteRecordingBundle(audioURL: URL, locales: [SpeechLocaleOption]) throws {
        try removeIfPresent(sidecarTranscriptURL(for: audioURL))
        try removeIfPresent(sidecarSummaryURL(for: audioURL))

        for locale in locales {
            try removeIfPresent(sidecarTranslatedTranscriptURL(for: audioURL, locale: locale))
            try removeIfPresent(sidecarTranslatedSummaryURL(for: audioURL, locale: locale))
        }

        try removeIfPresent(audioURL)
    }

    func renameRecordingAndSidecars(audioURL: URL, newName: String, locales: [SpeechLocaleOption]) throws -> URL {
        let cleaned = cleanFileName(newName)
        guard !cleaned.isEmpty else { return audioURL }

        let directory = audioURL.deletingLastPathComponent()
        let newAudioURL = directory
            .appendingPathComponent(cleaned)
            .appendingPathExtension(audioURL.pathExtension)

        if fileManager.fileExists(atPath: newAudioURL.path) {
            return audioURL
        }

        try fileManager.moveItem(at: audioURL, to: newAudioURL)

        try moveIfPresent(
            from: sidecarTranscriptURL(for: audioURL),
            to: sidecarTranscriptURL(for: newAudioURL)
        )
        try moveIfPresent(
            from: sidecarSummaryURL(for: audioURL),
            to: sidecarSummaryURL(for: newAudioURL)
        )

        for locale in locales {
            try moveIfPresent(
                from: sidecarTranslatedTranscriptURL(for: audioURL, locale: locale),
                to: sidecarTranslatedTranscriptURL(for: newAudioURL, locale: locale)
            )
            try moveIfPresent(
                from: sidecarTranslatedSummaryURL(for: audioURL, locale: locale),
                to: sidecarTranslatedSummaryURL(for: newAudioURL, locale: locale)
            )
        }

        return newAudioURL
    }

    private nonisolated func loadTextIfPresent(from url: URL) -> String {
        if let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            // Why: deletion must fail loudly so UI does not claim success on partial/failed delete.
            try fileManager.removeItem(at: url)
        }
    }

    private func moveIfPresent(from oldURL: URL, to newURL: URL) throws {
        guard fileManager.fileExists(atPath: oldURL.path) else { return }

        if fileManager.fileExists(atPath: newURL.path) {
            // Why: replacing an existing sidecar should fail loudly if removal fails.
            try fileManager.removeItem(at: newURL)
        }

        try fileManager.moveItem(at: oldURL, to: newURL)
    }

    private func cleanFileName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
