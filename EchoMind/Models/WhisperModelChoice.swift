//
//  WhisperModelChoice.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation

/// Shared model selection type used by Settings UI and download/install services.
enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case none
    case largeV3_547

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .largeV3_547: return "Large v3 (Compressed) ~550 MB"
        }
    }

    /// Folder name used by WhisperKit model repos (and by our on-device storage convention).
    var folderName: String {
        switch self {
        case .none: return ""
        case .largeV3_547: return "openai_whisper-large-v3-v20240930_547MB"
        }
    }
}
