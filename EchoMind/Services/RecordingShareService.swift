//
//  RecordingShareService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation

struct RecordingShareService {
    private let fileService: RecordingDetailFileService

    init(fileService: RecordingDetailFileService = RecordingDetailFileService()) {
        self.fileService = fileService
    }

    func makeShareItems(
        audioURL: URL,
        recordingTitle: String,
        style: ShareStylePreference
    ) -> [Any] {
        let loaded = fileService.loadTranscriptAndSummary(for: audioURL)
        let transcript = loaded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = loaded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let textPayload = composeTextPayload(title: recordingTitle, transcript: transcript, summary: summary)

        switch style {
        case .audioOnly:
            return [audioURL]
        case .textOnly:
            return textPayload.map { [$0] } ?? [audioURL]
        case .audioAndText:
            if let textPayload {
                return [audioURL, textPayload]
            }
            return [audioURL]
        }
    }

    private func composeTextPayload(title: String, transcript: String, summary: String) -> String? {
        var sections: [String] = []
        if !summary.isEmpty {
            sections.append("Summary\n\(summary)")
        }
        if !transcript.isEmpty {
            sections.append("Transcript\n\(transcript)")
        }

        guard !sections.isEmpty else { return nil }
        return "\(title)\n\n" + sections.joined(separator: "\n\n")
    }
}
