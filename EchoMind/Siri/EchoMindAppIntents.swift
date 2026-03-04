//
//  EchoMindAppIntents.swift
//  EchoMind
//
//  Created by Codex on 04.03.26.
//

import AppIntents
import Foundation

struct EchoMindAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EchoMindRecordIntent(),
            phrases: [
                "Record with \(.applicationName)",
                "Start recording with \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Begin recording in \(.applicationName)",
                "New recording in \(.applicationName)",
                "Take voice note in \(.applicationName)",
                "Capture note in \(.applicationName)"
            ],
            shortTitle: "Record",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: EchoMindTranscribeLastRecordingIntent(),
            phrases: [
                "Transcribe last record in \(.applicationName)",
                "Transcribe last recording in \(.applicationName)",
                "Transcribe latest recording in \(.applicationName)",
                "Transcript last recording in \(.applicationName)",
                "Convert last recording to text in \(.applicationName)",
                "Make transcript of last recording in \(.applicationName)"
            ],
            shortTitle: "Transcribe Last",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: EchoMindSummarizeLastRecordingIntent(),
            phrases: [
                "Summarize last record in \(.applicationName)",
                "Summarize last recording in \(.applicationName)",
                "Summarize latest recording in \(.applicationName)",
                "Summarize my last recording in \(.applicationName)",
                "Make summary of last recording in \(.applicationName)",
                "Create summary in \(.applicationName)"
            ],
            shortTitle: "Summarize Last",
            systemImageName: "text.alignleft"
        )
        AppShortcut(
            intent: EchoMindStopRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "Stop recording with \(.applicationName)",
                "Finish recording in \(.applicationName)",
                "End recording in \(.applicationName)",
                "Save recording in \(.applicationName)",
                "Done recording in \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: EchoMindPlayLastRecordingIntent(),
            phrases: [
                "Play last recording in \(.applicationName)",
                "Play last record in \(.applicationName)",
                "Play latest recording in \(.applicationName)",
                "Play newest recording in \(.applicationName)",
                "Play my last recording in \(.applicationName)",
                "Start playback in \(.applicationName)"
            ],
            shortTitle: "Play Last",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: EchoMindRenameLastRecordingIntent(),
            phrases: [
                "Name last recording in \(.applicationName)",
                "Rename last recording in \(.applicationName)",
                "Rename latest recording in \(.applicationName)",
                "Change last recording name in \(.applicationName)",
                "Change name of last recording in \(.applicationName)"
            ],
            shortTitle: "Rename Last",
            systemImageName: "pencil"
        )
        AppShortcut(
            intent: EchoMindDeleteLastRecordingIntent(),
            phrases: [
                "Delete last recording in \(.applicationName)",
                "Delete last record in \(.applicationName)",
                "Delete latest recording in \(.applicationName)",
                "Remove last recording in \(.applicationName)",
                "Erase last recording in \(.applicationName)"
            ],
            shortTitle: "Delete Last",
            systemImageName: "trash"
        )
    }
}

struct EchoMindRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Record with EchoMind"
    static var description = IntentDescription("Opens EchoMind and starts a new recording.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriLaunchRequestStore.queueStartRecording()
        return .result(dialog: IntentDialog("Opening EchoMind and starting a recording."))
    }
}

struct EchoMindTranscribeLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Last Record in EchoMind"
    static var description = IntentDescription("Transcribes your latest recording using your current EchoMind settings.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = await SiriRecordingIntentService()
        let transcriptResult = try await service.transcribeLastRecording()
        if transcriptResult.wasGenerated {
            return .result(value: transcriptResult.text, dialog: "Transcribed your latest recording.")
        }
        return .result(value: transcriptResult.text, dialog: "Your latest recording is already transcribed.")
    }
}

struct EchoMindSummarizeLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Last Record in EchoMind"
    static var description = IntentDescription("Summarizes your latest recording, transcribing it first if needed.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let service = await SiriRecordingIntentService()
        let summaryResult = try await service.summarizeLastRecording()
        if summaryResult.wasGenerated {
            return .result(value: summaryResult.text, dialog: "Summarized your latest recording.")
        }
        return .result(value: summaryResult.text, dialog: "Your latest recording already has a summary.")
    }
}

struct EchoMindStopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording in EchoMind"
    static var description = IntentDescription("Opens EchoMind and stops the active recording.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriLaunchRequestStore.queueStopRecording()
        return .result(dialog: "Opening EchoMind and stopping recording.")
    }
}

struct EchoMindPlayLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Last Recording in EchoMind"
    static var description = IntentDescription("Opens EchoMind and plays your latest recording.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = await SiriRecordingIntentService()
        let latestRecordingTitle = try await service.lastRecordingTitle()
        SiriLaunchRequestStore.queuePlayLastRecording()
        return .result(dialog: "Opening EchoMind and playing \(latestRecordingTitle).")
    }
}

struct EchoMindRenameLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Name Last Recording in EchoMind"
    static var description = IntentDescription("Renames your latest recording and all related sidecar files.")

    @Parameter(title: "New Name")
    var newName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = await SiriRecordingIntentService()
        let renamedTitle = try await service.renameLastRecording(to: newName)
        return .result(dialog: "Renamed your latest recording to \(renamedTitle).")
    }
}

struct EchoMindDeleteLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Last Recording in EchoMind"
    static var description = IntentDescription("Deletes your latest recording and its related sidecar files.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = await SiriRecordingIntentService()
        let deletedTitle = try await service.deleteLastRecording()
        return .result(dialog: "Deleted your latest recording, \(deletedTitle).")
    }
}

private struct SiriRecordingIntentService {
    // Why: keep this helper on the default main-actor isolation to avoid crossing non-Sendable dependencies.
    private static let defaultTranscriptionModelSettingKey = "settings.defaultTranscriptionModel"
    private static let transcriptionLanguageSettingKey = "settings.transcriptionLanguage"
    private static let summaryStyleSettingKey = "settings.summaryStyle"
    private static let whisperModelSettingKey = "settings.whisperModel"

    private let repository: any RecordingRepository
    private let fileService: RecordingDetailFileService
    private let appleTranscriber: AppleSpeechFileTranscriber
    private let whisperTranscriber: WhisperFileTranscriber
    private let whisperModelManager: WhisperModelManager
    private let defaults: UserDefaults

    init(
        repository: any RecordingRepository = FileSystemRecordingRepository(),
        fileService: RecordingDetailFileService = RecordingDetailFileService(),
        appleTranscriber: AppleSpeechFileTranscriber = AppleSpeechFileTranscriber(),
        whisperTranscriber: WhisperFileTranscriber = WhisperFileTranscriber(),
        whisperModelManager: WhisperModelManager = WhisperModelManager(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.fileService = fileService
        self.appleTranscriber = appleTranscriber
        self.whisperTranscriber = whisperTranscriber
        self.whisperModelManager = whisperModelManager
        self.defaults = defaults
    }

    struct TextResult {
        let text: String
        let wasGenerated: Bool
    }

    func transcribeLastRecording() async throws -> TextResult {
        let recording = try await loadLastRecording()
        let existingTranscript = normalized(fileService.loadTranscriptAndSummary(for: recording.url).transcript)
        if !existingTranscript.isEmpty {
            return TextResult(text: existingTranscript, wasGenerated: false)
        }

        let transcript = try await transcribeAudio(at: recording.url)
        guard !transcript.isEmpty else {
            throw SiriIntentError.emptyTranscript
        }

        try fileService.saveTranscript(transcript, for: recording.url)
        return TextResult(text: transcript, wasGenerated: true)
    }

    func summarizeLastRecording() async throws -> TextResult {
        let recording = try await loadLastRecording()
        let loaded = fileService.loadTranscriptAndSummary(for: recording.url)
        let existingSummary = normalized(loaded.summary)
        if !existingSummary.isEmpty {
            return TextResult(text: existingSummary, wasGenerated: false)
        }

        let transcript = try await transcriptForSummary(from: loaded.transcript, audioURL: recording.url)
        let summaryStyleRawValue = defaults.string(forKey: Self.summaryStyleSettingKey) ?? "balanced"
        let summary = normalized(try await OnDeviceAIService.summarize(transcript, styleRawValue: summaryStyleRawValue))

        guard !summary.isEmpty else {
            throw SiriIntentError.emptySummary
        }

        try fileService.saveSummary(summary, for: recording.url)
        return TextResult(text: summary, wasGenerated: true)
    }

    func lastRecording() async throws -> RecordingFile {
        try await loadLastRecording()
    }

    func lastRecordingTitle() async throws -> String {
        // Why: intents can pass plain strings safely without crossing actor-isolated model properties.
        let recording = try await loadLastRecording()
        return recording.displayTitle
    }

    func renameLastRecording(to newName: String) async throws -> String {
        let recording = try await loadLastRecording()
        let cleanedName = normalized(newName)
        guard !cleanedName.isEmpty else {
            throw SiriIntentError.invalidRecordingName
        }

        let renamedURL = try fileService.renameRecordingAndSidecars(
            audioURL: recording.url,
            newName: cleanedName,
            locales: SpeechLocaleOption.allCases
        )

        guard renamedURL != recording.url else {
            throw SiriIntentError.renameNotApplied
        }

        return renamedURL.deletingPathExtension().lastPathComponent
    }

    func deleteLastRecording() async throws -> String {
        let recording = try await loadLastRecording()
        try fileService.deleteRecordingBundle(audioURL: recording.url, locales: SpeechLocaleOption.allCases)
        return recording.displayTitle
    }

    private func transcriptForSummary(from cachedTranscript: String, audioURL: URL) async throws -> String {
        let existingTranscript = normalized(cachedTranscript)
        if !existingTranscript.isEmpty {
            return existingTranscript
        }

        let generatedTranscript = try await transcribeAudio(at: audioURL)
        guard !generatedTranscript.isEmpty else {
            throw SiriIntentError.emptyTranscript
        }

        try fileService.saveTranscript(generatedTranscript, for: audioURL)
        return generatedTranscript
    }

    private func loadLastRecording() async throws -> RecordingFile {
        let recent = await repository.loadRecentRecordings(limit: 1)
        guard let latest = recent.first else {
            throw SiriIntentError.noRecordings
        }
        return latest
    }

    private func transcribeAudio(at audioURL: URL) async throws -> String {
        let engineRawValue = defaults.string(forKey: Self.defaultTranscriptionModelSettingKey)
        let engine = TranscriptionEngine(rawValue: engineRawValue ?? "") ?? .appleSpeech
        let languageRawValue = defaults.string(forKey: Self.transcriptionLanguageSettingKey)
        let language = TranscriptionLanguage(rawValue: languageRawValue ?? "") ?? .auto

        switch engine {
        case .appleSpeech:
            try await AppleSpeechFileTranscriber.ensureAuthorized()
            return normalized(try await appleTranscriber.transcribeFile(url: audioURL, locale: locale(for: language)))

        case .whisperBasic:
            return normalized(try await whisperTranscriber.transcribeFile(
                url: audioURL,
                model: .base,
                languageCode: whisperBasicLanguageCode(for: language),
                localModelFolderPath: nil
            ))

        case .whisperLarge:
            let whisperModelRawValue = defaults.string(forKey: Self.whisperModelSettingKey)
            let selectedModel = WhisperModelChoice(rawValue: whisperModelRawValue ?? "") ?? .largeV3_547
            let localModelFolderPath = whisperModelManager.installedModelFolderPath(for: selectedModel)
            return normalized(try await whisperTranscriber.transcribeFile(
                url: audioURL,
                model: .largeV3,
                languageCode: whisperLargeLanguageCode(for: language),
                localModelFolderPath: localModelFolderPath
            ))
        }
    }

    private func locale(for language: TranscriptionLanguage) -> Locale {
        switch language {
        case .auto:
            return Locale.current
        case .en:
            return Locale(identifier: "en-US")
        case .de:
            return Locale(identifier: "de-DE")
        case .uk:
            return Locale(identifier: "uk-UA")
        case .ru:
            return Locale(identifier: "ru-RU")
        }
    }

    private func whisperBasicLanguageCode(for language: TranscriptionLanguage) -> String? {
        switch language {
        case .auto:
            return Locale.current.language.languageCode?.identifier
        case .en:
            return "en"
        case .de:
            return "de"
        case .uk:
            return "uk"
        case .ru:
            return "ru"
        }
    }

    private func whisperLargeLanguageCode(for language: TranscriptionLanguage) -> String? {
        switch language {
        case .auto:
            // Why: for the large model, keep language auto-detection enabled by default.
            return nil
        case .en:
            return "en"
        case .de:
            return "de"
        case .uk:
            return "uk"
        case .ru:
            return "ru"
        }
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SiriIntentError: LocalizedError {
    case noRecordings
    case emptyTranscript
    case emptySummary
    case invalidRecordingName
    case renameNotApplied

    var errorDescription: String? {
        switch self {
        case .noRecordings:
            return "No recordings were found in EchoMind."
        case .emptyTranscript:
            return "Transcription returned empty text."
        case .emptySummary:
            return "Summary returned empty text."
        case .invalidRecordingName:
            return "Please provide a non-empty recording name."
        case .renameNotApplied:
            return "Rename was not applied because the name is unchanged or already exists."
        }
    }
}
