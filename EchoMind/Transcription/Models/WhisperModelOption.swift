//
//  WhisperModelOption.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Combine

enum WhisperModelOption: String, CaseIterable, Identifiable, Hashable {
    case tiny
    case base
    case small
    case medium
    case largeV3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiny: return "Whisper tiny"
        case .base: return "Whisper base"
        case .small: return "Whisper small"
        case .medium: return "Whisper medium"
        case .largeV3: return "Whisper large-v3"
        }
    }

    var shortTitle: String {
        switch self {
        case .tiny: return "tiny"
        case .base: return "base"
        case .small: return "small"
        case .medium: return "medium"
        case .largeV3: return "large-v3"
        }
    }

    /// Identifier used by WhisperKit / engines that expect model ids.
    var modelId: String {
        switch self {
        case .tiny: return "tiny"
        case .base: return "base"
        case .small: return "small"
        case .medium: return "medium"
        case .largeV3: return "large-v3"
        }
    }
}
