//
//  BackgroundTranscriptionManager.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import BackgroundTasks
import AVFoundation

actor BackgroundTranscriptionManager {
    static let shared = BackgroundTranscriptionManager()
    static let taskIdentifier = "com.sashastepanov.EchoMind.transcription.processing"

    private let fileService: RecordingDetailFileService
    private let appleTranscriber: AppleSpeechFileTranscriber
    private let whisperTranscriber: WhisperFileTranscriber
    private let whisperModelManager: WhisperModelManager

    private var didLoadJobs = false
    private var jobs: [BackgroundTranscriptionJob] = []
    private var isProcessing = false

    init(
        fileService: RecordingDetailFileService = RecordingDetailFileService(),
        appleTranscriber: AppleSpeechFileTranscriber = AppleSpeechFileTranscriber(),
        whisperTranscriber: WhisperFileTranscriber = WhisperFileTranscriber(),
        whisperModelManager: WhisperModelManager = WhisperModelManager()
    ) {
        self.fileService = fileService
        self.appleTranscriber = appleTranscriber
        self.whisperTranscriber = whisperTranscriber
        self.whisperModelManager = whisperModelManager
    }

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task {
                await BackgroundTranscriptionManager.shared.handle(processingTask: processingTask)
            }
        }
    }

    static func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Why: queue is persisted; if scheduling fails now, app can retry later.
        }
    }

    func enqueueTranscription(
        audioURL: URL,
        engine: TranscriptionEngine,
        language: TranscriptionLanguage
    ) async {
        await loadJobsIfNeeded()

        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        let existingTranscript = fileService.loadTranscriptAndSummary(for: audioURL).transcript
        guard existingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if jobs.contains(where: { $0.audioFilePath == audioURL.path }) {
            return
        }

        let now = Date()
        let job = BackgroundTranscriptionJob(
            id: UUID(),
            audioFilePath: audioURL.path,
            engineRawValue: engine.rawValue,
            languageRawValue: language.rawValue,
            chunkDurationSeconds: 60,
            nextChunkIndex: 0,
            partialTranscripts: [],
            createdAt: now,
            updatedAt: now
        )

        jobs.append(job)
        await saveJobs()
        Self.scheduleBackgroundProcessing()
    }

    func processPendingJobsNow(maxChunks: Int = 1) async {
        _ = await processPendingJobs(maxChunks: max(1, maxChunks), cancellationFlag: nil)
    }

    func handle(processingTask: BGProcessingTask) async {
        let cancellationFlag = CancellationFlag()
        processingTask.expirationHandler = {
            cancellationFlag.cancel()
        }

        let success = await processPendingJobs(maxChunks: 4, cancellationFlag: cancellationFlag)
        processingTask.setTaskCompleted(success: success)

        if await hasPendingJobs() {
            Self.scheduleBackgroundProcessing()
        }
    }

    private func hasPendingJobs() async -> Bool {
        await loadJobsIfNeeded()
        return !jobs.isEmpty
    }

    private func processPendingJobs(maxChunks: Int, cancellationFlag: CancellationFlag?) async -> Bool {
        await loadJobsIfNeeded()

        guard !jobs.isEmpty else { return true }
        guard !isProcessing else { return true }

        isProcessing = true
        defer { isProcessing = false }

        var chunksProcessed = 0
        while chunksProcessed < maxChunks && !jobs.isEmpty {
            if cancellationFlag?.isCancelled == true {
                await saveJobs()
                return false
            }

            var job = jobs[0]

            do {
                let outcome = try await processSingleChunk(for: &job)
                switch outcome {
                case .progressed:
                    jobs[0] = job
                case .completed(let transcript):
                    try fileService.saveTranscript(transcript, for: job.audioURL)
                    jobs.removeFirst()
                }
            } catch {
                // Why: avoid infinite retries on a permanently failing job.
                jobs.removeFirst()
            }

            chunksProcessed += 1
            await saveJobs()
        }

        return true
    }

    private enum ChunkOutcome {
        case progressed
        case completed(String)
    }

    private func processSingleChunk(for job: inout BackgroundTranscriptionJob) async throws -> ChunkOutcome {
        let audioURL = job.audioURL
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw NSError(
                domain: "BackgroundTranscription",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio file no longer exists."]
            )
        }

        let asset = AVURLAsset(url: audioURL)
        let assetDuration = try await asset.load(.duration)
        let totalDurationSeconds = max(0.01, CMTimeGetSeconds(assetDuration))
        let totalChunks = max(1, Int(ceil(totalDurationSeconds / job.chunkDurationSeconds)))

        if job.nextChunkIndex >= totalChunks {
            let transcript = job.partialTranscripts.joined(separator: "\n")
            return .completed(transcript)
        }

        let chunkStart = Double(job.nextChunkIndex) * job.chunkDurationSeconds
        let chunkDuration = min(job.chunkDurationSeconds, totalDurationSeconds - chunkStart)
        let chunkURL = try await exportChunk(
            from: audioURL,
            jobID: job.id,
            chunkIndex: job.nextChunkIndex,
            startSeconds: chunkStart,
            durationSeconds: max(0.01, chunkDuration)
        )
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        let chunkText = try await transcribeChunk(
            chunkURL: chunkURL,
            engine: job.engine,
            language: job.language
        )

        let cleaned = chunkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            job.partialTranscripts.append(cleaned)
        }
        job.nextChunkIndex += 1
        job.updatedAt = Date()

        if job.nextChunkIndex >= totalChunks {
            let transcript = job.partialTranscripts.joined(separator: "\n")
            return .completed(transcript)
        }

        return .progressed
    }

    private func exportChunk(
        from audioURL: URL,
        jobID: UUID,
        chunkIndex: Int,
        startSeconds: Double,
        durationSeconds: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "BackgroundTranscription",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create audio exporter for background chunking."]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg_transcription_\(jobID.uuidString)_\(chunkIndex).m4a")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )

        try await exporter.export(to: outputURL, as: .m4a)

        return outputURL
    }

    private func transcribeChunk(
        chunkURL: URL,
        engine: TranscriptionEngine,
        language: TranscriptionLanguage
    ) async throws -> String {
        switch engine {
        case .appleSpeech:
            try await AppleSpeechFileTranscriber.ensureAuthorized()
            return try await appleTranscriber.transcribeFile(url: chunkURL, locale: locale(for: language))

        case .whisperBasic:
            return try await whisperTranscriber.transcribeFile(
                url: chunkURL,
                model: .base,
                languageCode: whisperBasicLanguageCode(for: language),
                localModelFolderPath: nil
            )

        case .whisperLarge:
            let localModelFolderPath = await whisperModelManager.installedModelFolderPath(for: .largeV3_547)
            return try await whisperTranscriber.transcribeFile(
                url: chunkURL,
                model: .largeV3,
                languageCode: whisperLargeLanguageCode(for: language),
                localModelFolderPath: localModelFolderPath
            )
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
            // Why: for large model, let Whisper auto-detect language in background processing.
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

    private func loadJobsIfNeeded() async {
        guard !didLoadJobs else { return }
        defer { didLoadJobs = true }

        let url = jobsFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BackgroundTranscriptionJob].self, from: data) else {
            jobs = []
            return
        }

        jobs = decoded
    }

    private func saveJobs() async {
        let url = jobsFileURL()
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func jobsFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("EchoMind", isDirectory: true)
            .appendingPathComponent("BackgroundTranscription", isDirectory: true)
            .appendingPathComponent("jobs.json")
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancelled = false

    nonisolated init() {}

    nonisolated var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
