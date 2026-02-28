//
//  WhisperFileTranscriber.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//


internal import Speech
#if canImport(WhisperKit)
import WhisperKit
#endif




final class WhisperFileTranscriber {
    func transcribeFile(url: URL, model: WhisperModelOption, languageCode: String?) async throws -> String {
        #if canImport(WhisperKit)
        // WhisperKit API can differ by version. This wrapper intentionally keeps the call site small.
        // If your WhisperKit version uses different types, adjust only inside this file.

        // A minimal, practical approach:
        // - Load model (large-v3)
        // - Transcribe the audio file
        // Note: Depending on your WhisperKit version, you may need to provide a config.

        let whisper = try await WhisperKit(model: model.modelId)
        let result: Any

        if let languageCode, !languageCode.isEmpty {
            // Try options-based API first (name may vary by WhisperKit version).
            // If this doesn't compile, we’ll adjust using the signature from your RecordingDetail file.
            let opts = DecodingOptions(task: .transcribe, language: languageCode)
            result = try await whisper.transcribe(audioPath: url.path, decodeOptions: opts)
        } else {
            result = try await whisper.transcribe(audioPath: url.path)
        }
        

        // Extract text safely (no KVC / ObjC bridging).
        if let text = extractText(from: result) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }

        // Fallback
        throw NSError(domain: "WhisperFileTranscriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected Whisper result format."])
        #else
        throw NSError(
            domain: "WhisperFileTranscriber",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit is not installed. Add WhisperKit (SPM) to enable Whisper large-v3 transcription."]
        )
        #endif
    }

    private func extractText(from any: Any) -> String? {
        // Fast paths
        if let s = any as? String { return s }

        // Generic reflection fallback: look for a `text` property or join `segments[].text`.
        let mirror = Mirror(reflecting: any)

        // 1) Direct `text`
        if let direct = mirror.children.first(where: { $0.label == "text" })?.value as? String {
            return direct
        }

        // 2) segments -> [Segment] where Segment has `text`
        if let segChild = mirror.children.first(where: { $0.label == "segments" }) {
            if let joined = joinSegmentTexts(from: segChild.value) {
                return joined
            }
        }

        // 3) Nested common wrappers: sometimes result is wrapped
        for child in mirror.children {
            if let text = extractText(from: child.value) {
                return text
            }
        }

        return nil
    }

    private func joinSegmentTexts(from any: Any) -> String? {
        // Handle arrays
        let mirror = Mirror(reflecting: any)
        guard mirror.displayStyle == .collection else { return nil }

        var parts: [String] = []
        parts.reserveCapacity(mirror.children.count)

        for child in mirror.children {
            // Segment may be a struct/class with `text`.
            if let text = Mirror(reflecting: child.value).children.first(where: { $0.label == "text" })?.value as? String {
                parts.append(text)
                continue
            }
            // Or nested
            if let nested = extractText(from: child.value) {
                parts.append(nested)
            }
        }

        let joined = parts.joined()
        return joined.isEmpty ? nil : joined
    }
}

