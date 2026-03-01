//
//  VoiceMemoImportService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation

protocol VoiceMemoImporting {
    func importAudioFile(from sourceURL: URL) throws -> URL
}

struct VoiceMemoImportService: VoiceMemoImporting {
    func importAudioFile(from sourceURL: URL) throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "VoiceMemoImportService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access documents folder."])
        }

        let didAccessScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let pathExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let baseName = sanitizedBaseName(from: sourceURL.deletingPathExtension().lastPathComponent)
        let preferredFileName = "\(baseName).\(pathExtension)"
        let destinationURL = uniqueDestinationURL(in: documentsDirectory, preferredFileName: preferredFileName)

        // Why: copy external files into app-owned storage so existing repository/transcription flow can use them.
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func sanitizedBaseName(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safe.isEmpty ? "Imported Voice Memo" : safe
    }

    private func uniqueDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let preferredURL = directory.appendingPathComponent(preferredFileName)
        guard !FileManager.default.fileExists(atPath: preferredURL.path) else {
            let ext = preferredURL.pathExtension
            let base = preferredURL.deletingPathExtension().lastPathComponent

            for index in 1...999 {
                let nextName = "\(base)-\(index)." + ext
                let candidateURL = directory.appendingPathComponent(nextName)
                if !FileManager.default.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
            }

            return directory.appendingPathComponent(UUID().uuidString + "." + ext)
        }

        return preferredURL
    }
}

