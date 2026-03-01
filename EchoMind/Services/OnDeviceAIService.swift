//
//  OnDeviceAIService.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import FoundationModels

enum OnDeviceAIService {
    static func summarize(_ text: String) async throws -> String {
        let model = SystemLanguageModel.default
        if !model.isAvailable {
            throw NSError(
                domain: "OnDeviceSummarizer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device/settings. Try enabling Apple Intelligence or use a fallback."]
            )
        }

        let session = LanguageModelSession()
        let prompt = "Summarize the following transcript in 3-5 concise bullet points. Keep it short and factual.\n\n\(text)"
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
                userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device/settings."]
            )
        }

        let session = LanguageModelSession()
        let prompt = "Generate a short title (3-6 words) for this transcript. Only output the title, nothing else.\n\n\(text)"
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

    static func translateWithFoundationModels(text: String, targetLanguageDisplayName: String) async throws -> String {
        let model = SystemLanguageModel.default
        if !model.isAvailable {
            throw NSError(
                domain: "OnDeviceTranslator",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device/settings."]
            )
        }

        let session = LanguageModelSession()
        let prompt = "Translate the following text into \(targetLanguageDisplayName). Be accurate and natural. Preserve bullets/line breaks. Output ONLY the translation.\n\n\(text)"

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.2)
        )

        let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty {
            throw NSError(
                domain: "OnDeviceTranslator",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Translation returned empty text."]
            )
        }

        return out
    }
}
