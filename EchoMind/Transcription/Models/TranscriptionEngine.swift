//
//  TranscriptionEngine.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Foundation

// MARK: - Transcription engine + Whisper model

enum TranscriptionEngine: String, CaseIterable, Identifiable, Hashable {
    case whisperBasic
    case whisperLarge
    case appleSpeech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperBasic: return "Whisper Basic"
        case .whisperLarge: return "Whisper Large"
        case .appleSpeech: return "Apple"
        }
    }

    var systemImage: String {
        switch self {
        case .whisperBasic, .whisperLarge: return "waveform"
        case .appleSpeech: return "mic"
        }
    }

    var isWhisper: Bool {
        switch self {
        case .whisperBasic, .whisperLarge:
            return true
        case .appleSpeech:
            return false
        }
    }
}
