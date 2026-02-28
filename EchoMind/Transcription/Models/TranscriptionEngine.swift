//
//  TranscriptionEngine.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Foundation

// MARK: - Transcription engine + Whisper model

enum TranscriptionEngine: String, CaseIterable, Identifiable, Hashable {
    case whisper
    case appleSpeech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisper: return "Whisper"
        case .appleSpeech: return "Apple"
        }
    }

    var systemImage: String {
        switch self {
        case .whisper: return "waveform"
        case .appleSpeech: return "mic"
        }
    }
}
