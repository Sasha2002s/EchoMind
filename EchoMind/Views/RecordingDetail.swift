//
//  RecordingDetail.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//


import SwiftUI
import Foundation
import FoundationModels
#if canImport(Translation)
import Translation
#endif



// MARK: - Detail

struct RecordingDetailView: View {
    let item: RecordingFile
    @ObservedObject var player: LibraryAudioPlayer
    init(item: RecordingFile, player: LibraryAudioPlayer) {
            self.item = item
            self.player = player
            _currentAudioURL = State(initialValue: item.url)
        }
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteError: String? = nil

    @State private var transcriptText: String = ""
    @State private var currentAudioURL: URL
    @State private var isTranscriptHidden: Bool = false
    @State private var summaryText: String = ""
    @State private var isSummaryHidden: Bool = false
    @State private var isSummarizing: Bool = false
    @State private var summaryError: String? = nil

    @State private var translatedSummaryText: String = ""
    @State private var isTranslatingSummary: Bool = false
    @State private var translationError: String? = nil
    @State private var selectedSummaryTranslationLocale: SpeechLocaleOption = .system
#if canImport(Translation)
    @State private var summaryTranslationConfiguration: TranslationSession.Configuration? = nil
#endif
    
    
    @State private var isLoadingTranscript: Bool = false
    @State private var transcriptionError: String? = nil
    @State private var isTranscribing: Bool = false
    @State private var whisperStatus: String? = nil

    @State private var selectedEngine: TranscriptionEngine = .whisper
    @State private var selectedSpeechLocale: SpeechLocaleOption = .system
    @State private var selectedWhisperLocale: SpeechLocaleOption = .system
    @State private var selectedWhisperModel: WhisperModelOption = .base

    private let appleTranscriber = AppleSpeechFileTranscriber()
    private let whisperTranscriber = WhisperFileTranscriber()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                playbackCard

                transcriptionCard

                summarizeButton

                deleteButton
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadTranscript()
            loadTranslatedSummaryIfExists()
        }
        .onChange(of: selectedSummaryTranslationLocale) { _ in
            loadTranslatedSummaryIfExists()
        }
#if canImport(Translation)
        .translationTask(summaryTranslationConfiguration) { session in
            do {
                // This API does not work on simulator; must be tested on-device.
                let response = try await session.translate(summaryText)
                let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if out.isEmpty {
                    translationError = "Translation returned empty text."
                } else {
                    translatedSummaryText = out
                    try? saveTranslatedSummary(out, locale: selectedSummaryTranslationLocale)
                }
            } catch {
                translationError = "Translation failed: \(error.localizedDescription)"
            }

            // Reset config so the task doesn't re-run unnecessarily.
            summaryTranslationConfiguration = nil
            isTranslatingSummary = false
        }
#endif
        .onDisappear {
            // Stop if this detail screen was the one playing.
            if player.isPlaying(id: item.id) {
                player.stop()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayTitleForCurrentFile)
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                Text(item.createdAtFormatted)
                Text("•")
                Text(item.durationFormatted)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var displayTitleForCurrentFile: String {
        let base = currentAudioURL.deletingPathExtension().lastPathComponent
        if base.lowercased().hasPrefix("recording_") {
            return "Recording \(item.createdAtFormatted)"
        }
        return base
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playback")
                    .font(.headline)

                Spacer()

                ShareLink(item: currentAudioURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Export audio")

                Button {
                    player.toggle(url: currentAudioURL, id: item.id)
                } label: {
                    Image(systemName: player.isPlaying(id: item.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(player.isPlaying(id: item.id) ? "Pause" : "Play")
            }

            // timeline
            HStack {
                Text(player.isLoaded(id: item.id) ? player.currentTimeFormatted : "0:00")
                Spacer()
                Text(player.isLoaded(id: item.id) ? player.totalDurationFormatted : item.durationFormatted)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // seek slider (fast-forward/rewind)
            Slider(
                value: Binding(
                    get: {
                        player.isLoaded(id: item.id) ? player.currentTime : 0
                    },
                    set: { newValue in
                        if player.isLoaded(id: item.id) {
                            player.seek(to: newValue)
                        }
                    }
                ),
                in: 0...(max(player.isLoaded(id: item.id) ? player.totalDuration : item.duration, 0.01))
            )
            .disabled(!player.isLoaded(id: item.id))
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                if isLoadingTranscript || isTranscribing {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Engine")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Picker("Engine", selection: $selectedEngine) {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                    } label: {
                        Label(selectedEngine.title, systemImage: selectedEngine.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                    .menuOrder(.fixed)
                }

                if selectedEngine == .appleSpeech {
                    HStack {
                        Text("Language")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Picker("Language", selection: $selectedSpeechLocale) {
                                ForEach(SpeechLocaleOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(selectedSpeechLocale.shortTitle, systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuOrder(.fixed)
                    }
                } else {
                    HStack {
                        Text("Language")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Picker("Language", selection: $selectedWhisperLocale) {
                                ForEach(SpeechLocaleOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(selectedWhisperLocale.shortTitle, systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuOrder(.fixed)
                    }
                }
            }

            let trimmedTranscript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedTranscript.isEmpty {
                Text("No transcription yet. You can add transcription later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTranscriptHidden.toggle()
                    }
                } label: {
                    Label(isTranscriptHidden ? "Show transcription" : "Hide transcription",
                          systemImage: isTranscriptHidden ? "chevron.down" : "chevron.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !isTranscriptHidden {
                    Text(transcriptText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            let trimmedSummary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedSummary.isEmpty {
                Divider().padding(.vertical, 4)

                Text("Summary")
                    .font(.headline)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSummaryHidden.toggle()
                    }
                } label: {
                    Label(isSummaryHidden ? "Show summary" : "Hide summary",
                          systemImage: isSummaryHidden ? "chevron.down" : "chevron.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if isSummaryHidden {
                    EmptyView()
                } else {
                    Text(summaryText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    Divider().padding(.vertical, 4)

                    HStack {
                        Text("Translate summary")
                            .font(.headline)

                        Spacer()

                        Menu {
                            Picker("Translate to", selection: $selectedSummaryTranslationLocale) {
                                ForEach(SpeechLocaleOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(selectedSummaryTranslationLocale.shortTitle, systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuOrder(.fixed)
                    }

                    Button {
                        Task { await translateSummaryOnDevice() }
                    } label: {
                        Label(isTranslatingSummary ? "Translating…" : "Translate", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTranslatingSummary || summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !translatedSummaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Translation")
                            .font(.headline)

                        Text(translatedSummaryText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }

            if let summaryError {
                Text(summaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let translationError {
                Text(translationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let transcriptionError {
                Text(transcriptionError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let whisperStatus, selectedEngine == .whisper {
                Text(whisperStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await transcribe() }
            } label: {
                let hasTranscript = !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Label(
                    isTranscribing ? "Transcribing…" : (hasTranscript ? "Re-transcribe" : "Transcribe"),
                    systemImage: selectedEngine.systemImage
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isTranscribing)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summarizeButton: some View {
        Button {
            Task { await summarizeOnDevice() }
        } label: {
            let hasSummary = !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Label(isSummarizing ? "Summarizing…" : (hasSummary ? "Re-summarize" : "Summarize"), systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSummarizing)
        .accessibilityHint("Creates a short on-device summary from the transcript")
    }

    private var exportButton: some View {
        ShareLink(item: currentAudioURL) {
            Label("Export audio", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
    

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete recording", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteRecording() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the audio and its transcription.")
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "Unknown error")
        }
    }

    private var sidecarTranscriptURL: URL {
        currentAudioURL.deletingPathExtension().appendingPathExtension("txt")
    }

    private var sidecarSummaryURL: URL {
        currentAudioURL.deletingPathExtension().appendingPathExtension("summary.txt")
    }

    private func sidecarTranslatedSummaryURL(for option: SpeechLocaleOption) -> URL {
        let code = option.languageCode ?? "system"
        return currentAudioURL.deletingPathExtension().appendingPathExtension("summary.\(code).txt")
    }

#if canImport(Translation)
    private func targetLanguageForTranslationFramework() -> Locale.Language {
        // If user selected a specific language code, use it.
        if let code = selectedSummaryTranslationLocale.languageCode, !code.isEmpty {
            return Locale.Language(identifier: code)
        }

        // Otherwise default to the device language (or English if unavailable).
        let deviceCode = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.Language(identifier: deviceCode)
    }
#endif

    private func deleteRecording() async {
        // Stop playback if needed
        if player.isPlaying(id: item.id) {
            player.stop()
        }

        do {
            // Delete transcription sidecar if present
            if FileManager.default.fileExists(atPath: sidecarTranscriptURL.path) {
                try FileManager.default.removeItem(at: sidecarTranscriptURL)
            }

            // Delete summary sidecar if present
            if FileManager.default.fileExists(atPath: sidecarSummaryURL.path) {
                try FileManager.default.removeItem(at: sidecarSummaryURL)
            }
            // Delete translated summary sidecars if present (best-effort)
            for option in SpeechLocaleOption.allCases {
                let url = sidecarTranslatedSummaryURL(for: option)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            // Delete the audio file
            if FileManager.default.fileExists(atPath: currentAudioURL.path) {
                try FileManager.default.removeItem(at: currentAudioURL)
            }

            // Dismiss detail view after deletion
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func loadTranscript() {
        isLoadingTranscript = true
        transcriptionError = nil
        summaryError = nil
        translationError = nil
        defer { isLoadingTranscript = false }

        // Transcript
        if let data = try? Data(contentsOf: sidecarTranscriptURL),
           let str = String(data: data, encoding: .utf8) {
            transcriptText = str
        } else {
            transcriptText = ""
        }

        // Summary
        if let data = try? Data(contentsOf: sidecarSummaryURL),
           let str = String(data: data, encoding: .utf8) {
            summaryText = str
        } else {
            summaryText = ""
        }
    }

    private func saveTranscript(_ text: String) throws {
        let data = Data(text.utf8)
        try data.write(to: sidecarTranscriptURL, options: [.atomic])
    }

    private func saveSummary(_ text: String) throws {
        let data = Data(text.utf8)
        try data.write(to: sidecarSummaryURL, options: [.atomic])
    }

    private func saveTranslatedSummary(_ text: String, locale: SpeechLocaleOption) throws {
        let url = sidecarTranslatedSummaryURL(for: locale)
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
    }

    private func loadTranslatedSummaryIfExists() {
        let url = sidecarTranslatedSummaryURL(for: selectedSummaryTranslationLocale)
        if let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8) {
            translatedSummaryText = str
        } else {
            translatedSummaryText = ""
        }
    }

    private func transcribe() async {
        switch selectedEngine {
        case .appleSpeech:
            await transcribeWithAppleSpeech()
        case .whisper:
            await transcribeWithWhisper()
        }
    }

    private func summarizeOnDevice() async {
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
            async let summaryTask = OnDeviceSummarizer.summarize(text)
            async let titleTask = OnDeviceSummarizer.suggestTitle(text)

            let summary = try await summaryTask
            let suggestedTitle = try await titleTask

            summaryText = summary
            try saveSummary(summary)

            // stop playback before moving file
            if player.isPlaying(id: item.id) {
                player.stop()
            }

            try renameRecordingAndSidecar(to: suggestedTitle)
        } catch {
            summaryError = error.localizedDescription
        }
    }

    private func translateSummaryOnDevice() async {
        guard !isTranslatingSummary else { return }

        translationError = nil
        isTranslatingSummary = true

        let text = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            translationError = "Summarize first, then translate."
            isTranslatingSummary = false
            return
        }

#if canImport(Translation)
        // Use Apple's Translation framework (typically much better than small LLM prompts).
        // Source language = nil (auto-detect), target = user's selection (or device language).
        summaryTranslationConfiguration = TranslationSession.Configuration(
            source: nil,
            target: targetLanguageForTranslationFramework()
        )
        // The `.translationTask` modifier will finish the work and reset `isTranslatingSummary`.
        return
#else
        // Fallback to FoundationModels if Translation framework isn't available.
        defer { isTranslatingSummary = false }

        do {
            let model = SystemLanguageModel.default
            if !model.isAvailable {
                throw NSError(
                    domain: "OnDeviceTranslator",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "On-device AI isn’t available on this device/settings."]
                )
            }

            let session = LanguageModelSession()
            let target = selectedSummaryTranslationLocale.title
            let prompt = "Translate the following text into \(target). Be accurate and natural. Preserve bullets/line breaks. Output ONLY the translation.\n\n\(text)"

            // Lower temperature for more deterministic, faithful translation.
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.2)
            )

            let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty {
                translationError = "Translation returned empty text."
                return
            }

            translatedSummaryText = out
            try saveTranslatedSummary(out, locale: selectedSummaryTranslationLocale)
        } catch {
            translationError = error.localizedDescription
        }
#endif
    }

    private func renameRecordingAndSidecar(to newName: String) throws {
        let cleaned = newName
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return }

        let dir = currentAudioURL.deletingLastPathComponent()
        let newAudioURL = dir
            .appendingPathComponent(cleaned)
            .appendingPathExtension(currentAudioURL.pathExtension)

        // if name exists, keep current name
        if FileManager.default.fileExists(atPath: newAudioURL.path) { return }

        // move audio
        try FileManager.default.moveItem(at: currentAudioURL, to: newAudioURL)

        // move transcript sidecar if present
        let oldSidecar = currentAudioURL.deletingPathExtension().appendingPathExtension("txt")
        let newSidecar = newAudioURL.deletingPathExtension().appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: oldSidecar.path) {
            try FileManager.default.moveItem(at: oldSidecar, to: newSidecar)
        }

        // update state => UI updates immediately
        currentAudioURL = newAudioURL
    }

    private enum OnDeviceSummarizer {
        static func summarize(_ text: String) async throws -> String {
            // Basic availability check (device + Apple Intelligence state).
            let model = SystemLanguageModel.default
            if !model.isAvailable {
                throw NSError(
                    domain: "OnDeviceSummarizer",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "On-device AI isn’t available on this device/settings. Try enabling Apple Intelligence or use a fallback."]
                )
            }

            // Create a session (single-turn context is fine for this use case).
            let session = LanguageModelSession()

            // Keep prompt short and deterministic-ish.
            let prompt = "Summarize the following transcript in 3–5 concise bullet points. Keep it short and factual.\n\n\(text)"
            let response = try await session.respond(to: prompt)

            let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty {
                throw NSError(
                    domain: "OnDeviceSummarizer",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Summary returned empty text."]
                )
            }
            return out
        }
        static func suggestTitle(_ text: String) async throws -> String {
            let model = SystemLanguageModel.default
            if !model.isAvailable {
                throw NSError(
                    domain: "OnDeviceSummarizer",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "On-device AI isn’t available on this device/settings."]
                )
            }

            let session = LanguageModelSession()
            let prompt = "Generate a short title (3–6 words) for this transcript. Only output the title, nothing else.\n\n\(text)"
            let response = try await session.respond(to: prompt)

            let out = response.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if out.isEmpty {
                throw NSError(
                    domain: "OnDeviceSummarizer",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Title returned empty text."]
                )
            }

            return out
        }
    }

    private func transcribeWithWhisper() async {
        guard !isTranscribing else { return }

        transcriptionError = nil
        summaryError = nil
        summaryText = ""
        translatedSummaryText = ""
        translationError = nil
        whisperStatus = "Preparing \(selectedWhisperLocale.shortTitle)…"
        isTranscribing = true
        defer {
            isTranscribing = false
            whisperStatus = nil
        }

        // Ensure the file is reachable
        guard FileManager.default.fileExists(atPath: currentAudioURL.path) else {
            transcriptionError = "Audio file not found."
            return
        }

        do {
            whisperStatus = "Transcribing (\(selectedWhisperLocale.shortTitle))…"
            let started = Date()

            let result = try await withTimeout(seconds: 120) {
                try await whisperTranscriber.transcribeFile(
                    url: currentAudioURL,
                    model: selectedWhisperModel,
                    languageCode: selectedWhisperLocale.languageCode
                )
            }

            let elapsed = Date().timeIntervalSince(started)
            print("Whisper transcription finished in \(elapsed)s")

            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.isEmpty {
                transcriptionError = "Transcription returned empty text."
                return
            }

            transcriptText = cleaned
            try saveTranscript(cleaned)
        } catch {
            if (error as NSError).domain == "Timeout" {
                transcriptionError = "Whisper is taking too long (model download/first setup can take minutes). Try a smaller model first (tiny/base), keep the app open on Wi‑Fi, then retry large‑v3."
            } else {
                transcriptionError = "Transcription failed: \(error.localizedDescription)"
            }
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

    private func transcribeWithAppleSpeech() async {
        guard !isTranscribing else { return }

        transcriptionError = nil
        summaryError = nil
        summaryText = ""
        translatedSummaryText = ""
        translationError = nil
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            try await AppleSpeechFileTranscriber.ensureAuthorized()
        } catch {
            transcriptionError = error.localizedDescription
            return
        }

        // 2) Ensure the file is reachable
        guard FileManager.default.fileExists(atPath: currentAudioURL.path) else {
            transcriptionError = "Audio file not found."
            return
        }

        // 3) Transcribe
        do {
            let locale = selectedSpeechLocale.locale
            let result = try await appleTranscriber.transcribeFile(url: currentAudioURL, locale: locale)
            let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.isEmpty {
                transcriptionError = "Transcription returned empty text."
                return
            }

            transcriptText = cleaned
            try saveTranscript(cleaned)
        } catch {
            transcriptionError = "Transcription failed: \(error.localizedDescription)"
        }
    }
}

#Preview("Recording Detail") {
    NavigationStack {
        RecordingDetailView(
            item: LibraryView_PreviewsHelper.sampleRecordingFile(),
            player: LibraryAudioPlayer()
        )
    }
}





