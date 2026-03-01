//
//  RecordingExportService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

struct RecordingExportPayload {
    let data: Data
    let contentType: UTType
    let defaultFilename: String
}

struct RecordingExportService {
    private let fileService: RecordingDetailFileService

    init(fileService: RecordingDetailFileService = RecordingDetailFileService()) {
        self.fileService = fileService
    }

    func prepareExport(
        audioURL: URL,
        defaultName: String,
        format: ExportFormatPreference
    ) async throws -> RecordingExportPayload {
        let baseName = sanitizedBaseName(from: defaultName)

        switch format {
        case .txt, .md:
            let loaded = fileService.loadTranscriptAndSummary(for: audioURL)
            let transcript = loaded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = loaded.summary.trimmingCharacters(in: .whitespacesAndNewlines)

            let text = composeExportText(transcript: transcript, summary: summary, markdown: format == .md)
            guard !text.isEmpty else {
                throw NSError(
                    domain: "RecordingExportService",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "No transcription or summary found to export as text."]
                )
            }

            let data = Data(text.utf8)
            let contentType: UTType = (format == .md) ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText
            return RecordingExportPayload(
                data: data,
                contentType: contentType,
                defaultFilename: "\(baseName).\(format.fileExtension)"
            )

        case .m4a:
            let data = try await exportAudioData(audioURL: audioURL, target: .m4a)
            return RecordingExportPayload(
                data: data,
                contentType: UTType(filenameExtension: "m4a") ?? .audio,
                defaultFilename: "\(baseName).m4a"
            )

        case .wav:
            let data = try await exportAudioData(audioURL: audioURL, target: .wav)
            return RecordingExportPayload(
                data: data,
                contentType: .wav,
                defaultFilename: "\(baseName).wav"
            )
        }
    }

    private enum AudioExportTarget {
        case m4a
        case wav

        var fileExtension: String {
            switch self {
            case .m4a: return "m4a"
            case .wav: return "wav"
            }
        }

        var outputFileType: AVFileType {
            switch self {
            case .m4a: return .m4a
            case .wav: return .wav
            }
        }

        var presetName: String {
            switch self {
            case .m4a:
                return AVAssetExportPresetAppleM4A
            case .wav:
                // Why: WAV support depends on source/pipeline, so use passthrough and validate supported file types.
                return AVAssetExportPresetPassthrough
            }
        }
    }

    private func exportAudioData(audioURL: URL, target: AudioExportTarget) async throws -> Data {
        let sourceExtension = audioURL.pathExtension.lowercased()
        if sourceExtension == target.fileExtension {
            return try Data(contentsOf: audioURL)
        }

        let asset = AVURLAsset(url: audioURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: target.presetName) else {
            throw NSError(
                domain: "RecordingExportService",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio export session."]
            )
        }

        guard exporter.supportedFileTypes.contains(target.outputFileType) else {
            throw NSError(
                domain: "RecordingExportService",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "Export to .\(target.fileExtension) is not supported for this recording."]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(target.fileExtension)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = target.outputFileType
        exporter.shouldOptimizeForNetworkUse = true

        try await runExport(exporter)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(
                domain: "RecordingExportService",
                code: 23,
                userInfo: [NSLocalizedDescriptionKey: "Export finished but output file was not created."]
            )
        }

        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        return data
    }

    private func runExport(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? NSError(
                        domain: "RecordingExportService",
                        code: 24,
                        userInfo: [NSLocalizedDescriptionKey: "Audio export failed."]
                    ))
                case .cancelled:
                    continuation.resume(throwing: NSError(
                        domain: "RecordingExportService",
                        code: 25,
                        userInfo: [NSLocalizedDescriptionKey: "Audio export was cancelled."]
                    ))
                default:
                    continuation.resume(throwing: NSError(
                        domain: "RecordingExportService",
                        code: 26,
                        userInfo: [NSLocalizedDescriptionKey: "Audio export did not complete."]
                    ))
                }
            }
        }
    }

    private func composeExportText(transcript: String, summary: String, markdown: Bool) -> String {
        var parts: [String] = []

        if !summary.isEmpty {
            parts.append(markdown ? "## Summary\n\(summary)" : "Summary\n\(summary)")
        }
        if !transcript.isEmpty {
            parts.append(markdown ? "## Transcript\n\(transcript)" : "Transcript\n\(transcript)")
        }

        return parts.joined(separator: "\n\n")
    }

    private func sanitizedBaseName(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Recording" }

        let deletingExtension = (trimmed as NSString).deletingPathExtension
        let base = deletingExtension.isEmpty ? trimmed : deletingExtension
        return base.replacingOccurrences(of: "/", with: "-")
    }
}
