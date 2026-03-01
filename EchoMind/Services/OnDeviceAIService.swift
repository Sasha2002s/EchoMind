//
//  OnDeviceAIService.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import FoundationModels

enum OnDeviceAIService {
    private static let summaryChunkCharacterLimit = 3_000
    private static let summaryReduceCharacterLimit = 3_600
    private static let maxSummaryReductionPasses = 3
    private static let metadataAnalysisCharacterLimit = 2_800
    private static let fallbackSummaryChunkCharacterLimit = 1_500
    private static let fallbackSummaryReduceCharacterLimit = 1_800
    private static let fallbackMetadataAnalysisCharacterLimit = 1_200

    struct ReferenceCheckResult {
        let noteForSummary: String?
        let suggestedSongTitle: String?
    }

    static func summarize(_ text: String) async throws -> String {
        try ensureModelAvailable(for: "OnDeviceSummarizer")

        let normalized = normalizeInputText(text)
        guard !normalized.isEmpty else {
            throw NSError(
                domain: "OnDeviceSummarizer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Summary returned empty text."]
            )
        }

        let transcriptChunks = chunkText(normalized, maxCharacters: summaryChunkCharacterLimit)
        if transcriptChunks.count == 1 {
            return try await summarizeSingleTranscriptChunkWithFallback(
                transcriptChunks[0],
                chunkIndex: 1,
                chunkCount: 1
            )
        }

        var partialSummaries: [String] = []
        partialSummaries.reserveCapacity(transcriptChunks.count)

        for (index, chunk) in transcriptChunks.enumerated() {
            let chunkSummary = try await summarizeSingleTranscriptChunkWithFallback(
                chunk,
                chunkIndex: index + 1,
                chunkCount: transcriptChunks.count
            )
            partialSummaries.append(chunkSummary)
        }

        // Why: reduce long transcript summaries in stages so each model call stays inside context limits.
        var combinedSummary = partialSummaries.joined(separator: "\n\n")
        var pass = 0
        while combinedSummary.count > summaryReduceCharacterLimit && pass < maxSummaryReductionPasses {
            pass += 1
            let reductionChunks = chunkText(combinedSummary, maxCharacters: summaryReduceCharacterLimit)
            var reduced: [String] = []
            reduced.reserveCapacity(reductionChunks.count)

            for chunk in reductionChunks {
                reduced.append(try await compressIntermediateSummaryChunkWithFallback(chunk, pass: pass))
            }

            combinedSummary = reduced.joined(separator: "\n\n")
        }

        return try await finalizeSummaryWithFallback(from: combinedSummary)
    }

    static func checkForFamousReference(_ text: String) async throws -> ReferenceCheckResult {
        let model = SystemLanguageModel.default
        if !model.isAvailable {
            return ReferenceCheckResult(noteForSummary: nil, suggestedSongTitle: nil)
        }

        let source = sampledAnalysisText(from: text, maxCharacters: metadataAnalysisCharacterLimit)
        let prompt = """
        Analyze the transcript and detect whether it appears very close to either:
        1) a known song lyric
        2) a famous quote/phrase

        Return EXACTLY one line in this strict format:
        TYPE|TITLE|CONFIDENCE|NOTE

        Rules:
        - TYPE: NONE, LYRICS, or PHRASE
        - TITLE: song/phrase name, or "-" if unknown
        - CONFIDENCE: integer 0-100
        - NOTE: short sentence (max 20 words), or "-" if none
        - Do not include extra lines or explanations.

        Transcript:
        \(source)
        """

        let responseContent: String
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.0)
            )
            responseContent = response.content
        } catch {
            guard isContextWindowError(error) else { throw error }
            let fallbackSource = sampledAnalysisText(from: text, maxCharacters: fallbackMetadataAnalysisCharacterLimit)
            let fallbackPrompt = """
            Analyze the transcript and detect whether it appears very close to either:
            1) a known song lyric
            2) a famous quote/phrase

            Return EXACTLY one line in this strict format:
            TYPE|TITLE|CONFIDENCE|NOTE

            Rules:
            - TYPE: NONE, LYRICS, or PHRASE
            - TITLE: song/phrase name, or "-" if unknown
            - CONFIDENCE: integer 0-100
            - NOTE: short sentence (max 20 words), or "-" if none
            - Do not include extra lines or explanations.

            Transcript:
            \(fallbackSource)
            """
            let retrySession = LanguageModelSession()
            let response = try await retrySession.respond(
                to: fallbackPrompt,
                options: GenerationOptions(temperature: 0.0)
            )
            responseContent = response.content
        }

        let raw = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parseReferenceLine(raw)

        guard let parsed else {
            return ReferenceCheckResult(noteForSummary: nil, suggestedSongTitle: nil)
        }

        guard parsed.confidence >= 75 else {
            return ReferenceCheckResult(noteForSummary: nil, suggestedSongTitle: nil)
        }

        let titleText = parsed.title == "-" ? nil : parsed.title
        let noteText = parsed.note == "-" ? nil : parsed.note

        switch parsed.type {
        case "LYRICS":
            let note = noteText ?? "Possible match to known song lyrics."
            return ReferenceCheckResult(noteForSummary: note, suggestedSongTitle: titleText)
        case "PHRASE":
            let note = noteText ?? "Possible match to a known phrase."
            return ReferenceCheckResult(noteForSummary: note, suggestedSongTitle: nil)
        default:
            return ReferenceCheckResult(noteForSummary: nil, suggestedSongTitle: nil)
        }
    }

    private struct ParsedReferenceLine {
        let type: String
        let title: String
        let confidence: Int
        let note: String
    }

    private static func parseReferenceLine(_ raw: String) -> ParsedReferenceLine? {
        let firstLine = raw
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pieces = firstLine.split(separator: "|", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }

        let type = String(pieces[0]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let title = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let confidenceText = String(pieces[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = String(pieces[3]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard ["NONE", "LYRICS", "PHRASE"].contains(type),
              let confidence = Int(confidenceText) else {
            return nil
        }

        let clampedConfidence = max(0, min(100, confidence))
        return ParsedReferenceLine(type: type, title: title, confidence: clampedConfidence, note: note)
    }

    static func suggestTitle(_ text: String) async throws -> String {
        try ensureModelAvailable(for: "OnDeviceSummarizer", code: 3)

        let source = sampledAnalysisText(from: text, maxCharacters: metadataAnalysisCharacterLimit)
        let prompt = "Generate a short title (3-6 words) for this transcript. Only output the title, nothing else.\n\n\(source)"

        let responseContent: String
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            responseContent = response.content
        } catch {
            guard isContextWindowError(error) else { throw error }
            let fallbackSource = sampledAnalysisText(from: text, maxCharacters: fallbackMetadataAnalysisCharacterLimit)
            let fallbackPrompt = "Generate a short title (3-6 words) for this transcript. Only output the title, nothing else.\n\n\(fallbackSource)"
            let retrySession = LanguageModelSession()
            let response = try await retrySession.respond(to: fallbackPrompt)
            responseContent = response.content
        }

        let out = responseContent
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
        try ensureModelAvailable(for: "OnDeviceTranslator", code: 10)

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

    private static func ensureModelAvailable(for domain: String, code: Int = 1) throws {
        let model = SystemLanguageModel.default
        if !model.isAvailable {
            throw NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device/settings. Try enabling Apple Intelligence or use a fallback."]
            )
        }
    }

    private static func summarizeSingleTranscriptChunk(_ chunk: String, chunkIndex: Int, chunkCount: Int) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        You are summarizing transcript chunk \(chunkIndex) of \(chunkCount).
        Return 3-5 concise, factual bullet points.
        Avoid repetition and filler.

        Transcript chunk:
        \(chunk)
        """

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.1)
        )

        return try nonEmptyOutput(
            response.content,
            domain: "OnDeviceSummarizer",
            code: 2,
            fallbackMessage: "Summary returned empty text."
        )
    }

    private static func summarizeSingleTranscriptChunkWithFallback(
        _ chunk: String,
        chunkIndex: Int,
        chunkCount: Int
    ) async throws -> String {
        do {
            return try await summarizeSingleTranscriptChunk(
                chunk,
                chunkIndex: chunkIndex,
                chunkCount: chunkCount
            )
        } catch {
            guard isContextWindowError(error) else { throw error }

            let fallbackChunks = chunkText(chunk, maxCharacters: fallbackSummaryChunkCharacterLimit)
            if fallbackChunks.count <= 1 {
                throw error
            }

            var partials: [String] = []
            partials.reserveCapacity(fallbackChunks.count)

            for fallbackChunk in fallbackChunks {
                partials.append(
                    try await summarizeSingleTranscriptChunk(
                        fallbackChunk,
                        chunkIndex: chunkIndex,
                        chunkCount: chunkCount
                    )
                )
            }

            return partials.joined(separator: "\n")
        }
    }

    private static func compressIntermediateSummaryChunk(_ chunk: String, pass: Int) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        Compress the following summary notes into 3-5 short bullet points.
        Keep only key facts and remove duplicates.
        This is reduction pass \(pass).

        Notes:
        \(chunk)
        """

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.0)
        )

        return try nonEmptyOutput(
            response.content,
            domain: "OnDeviceSummarizer",
            code: 2,
            fallbackMessage: "Summary returned empty text."
        )
    }

    private static func compressIntermediateSummaryChunkWithFallback(_ chunk: String, pass: Int) async throws -> String {
        do {
            return try await compressIntermediateSummaryChunk(chunk, pass: pass)
        } catch {
            guard isContextWindowError(error) else { throw error }
            let shrinkChunk = sampledAnalysisText(from: chunk, maxCharacters: fallbackSummaryReduceCharacterLimit)
            return try await compressIntermediateSummaryChunk(shrinkChunk, pass: pass)
        }
    }

    private static func finalizeSummary(from combinedSummary: String) async throws -> String {
        let session = LanguageModelSession()
        let source = sampledAnalysisText(from: combinedSummary, maxCharacters: summaryReduceCharacterLimit)
        let prompt = """
        Produce the final summary as 3-5 concise bullet points.
        Keep it factual and readable.

        Source notes:
        \(source)
        """

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.1)
        )

        return try nonEmptyOutput(
            response.content,
            domain: "OnDeviceSummarizer",
            code: 2,
            fallbackMessage: "Summary returned empty text."
        )
    }

    private static func finalizeSummaryWithFallback(from combinedSummary: String) async throws -> String {
        do {
            return try await finalizeSummary(from: combinedSummary)
        } catch {
            guard isContextWindowError(error) else { throw error }
            let shrink = sampledAnalysisText(from: combinedSummary, maxCharacters: fallbackSummaryReduceCharacterLimit)
            return try await finalizeSummary(from: shrink)
        }
    }

    private static func nonEmptyOutput(
        _ raw: String,
        domain: String,
        code: Int,
        fallbackMessage: String
    ) throws -> String {
        let out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty {
            throw NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: fallbackMessage]
            )
        }
        return out
    }

    private static func normalizeInputText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chunkText(_ text: String, maxCharacters: Int) -> [String] {
        let normalized = normalizeInputText(text)
        guard !normalized.isEmpty else { return [] }
        guard normalized.count > maxCharacters else { return [normalized] }

        var chunks: [String] = []
        var current = ""

        for word in normalized.split(whereSeparator: \.isWhitespace) {
            let token = String(word)
            let candidate = current.isEmpty ? token : "\(current) \(token)"
            if candidate.count <= maxCharacters {
                current = candidate
            } else {
                if !current.isEmpty {
                    chunks.append(current)
                }

                if token.count <= maxCharacters {
                    current = token
                } else {
                    // Why: a very long token should not break chunking.
                    var start = token.startIndex
                    while start < token.endIndex {
                        let end = token.index(start, offsetBy: maxCharacters, limitedBy: token.endIndex) ?? token.endIndex
                        chunks.append(String(token[start..<end]))
                        start = end
                    }
                    current = ""
                }
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func sampledAnalysisText(from text: String, maxCharacters: Int) -> String {
        let normalized = normalizeInputText(text)
        guard normalized.count > maxCharacters else { return normalized }

        let part = max(600, maxCharacters / 3)
        let head = String(normalized.prefix(part))
        let tail = String(normalized.suffix(part))
        let center = middleSnippet(from: normalized, length: part)
        return "\(head)\n...\n\(center)\n...\n\(tail)"
    }

    private static func middleSnippet(from text: String, length: Int) -> String {
        guard !text.isEmpty else { return "" }
        guard text.count > length else { return text }

        let midpointOffset = text.count / 2
        let half = length / 2
        let startOffset = max(0, midpointOffset - half)
        let endOffset = min(text.count, startOffset + length)

        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end])
    }

    private static func isContextWindowError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let combined = [
            nsError.localizedDescription,
            nsError.localizedFailureReason ?? "",
            nsError.debugDescription
        ]
            .joined(separator: " ")
            .lowercased()

        return combined.contains("context window")
            || combined.contains("context length")
            || combined.contains("token limit")
            || combined.contains("too many tokens")
            || combined.contains("exceed")
    }
}
