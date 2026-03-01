//
//  BackgroundTranscriptionJob.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation

struct BackgroundTranscriptionJob: Codable, Identifiable {
    let id: UUID
    let audioFilePath: String
    let engineRawValue: String
    let languageRawValue: String
    let chunkDurationSeconds: Double
    var nextChunkIndex: Int
    var partialTranscripts: [String]
    let createdAt: Date
    var updatedAt: Date

    nonisolated var audioURL: URL {
        URL(fileURLWithPath: audioFilePath)
    }

    nonisolated var engine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRawValue) ?? .appleSpeech
    }

    nonisolated var language: TranscriptionLanguage {
        TranscriptionLanguage(rawValue: languageRawValue) ?? .auto
    }
}
