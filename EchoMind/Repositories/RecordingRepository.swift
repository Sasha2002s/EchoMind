//
//  RecordingRepository.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import AVFoundation

protocol RecordingRepository {
    func loadAllRecordings() async -> [RecordingFile]
    func loadRecentRecordings(limit: Int) async -> [RecordingFile]
}

struct FileSystemRecordingRepository: RecordingRepository {
    func loadAllRecordings() async -> [RecordingFile] {
        await loadRecordings(limit: nil)
    }

    func loadRecentRecordings(limit: Int) async -> [RecordingFile] {
        guard limit > 0 else { return [] }
        return await loadRecordings(limit: limit)
    }

    private func loadRecordings(limit: Int?) async -> [RecordingFile] {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let audioURLs = urls.filter { $0.pathExtension.lowercased() == "m4a" }
        let items = await withTaskGroup(of: RecordingFile?.self) { group in
            for url in audioURLs {
                group.addTask {
                    let values = try? url.resourceValues(
                        forKeys: [.contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey]
                    )
                    let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
                    let stableID = values?.fileResourceIdentifier.map { String(describing: $0) } ?? url.lastPathComponent
                    let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0

                    return RecordingFile(id: stableID, url: url, createdAt: createdAt, duration: duration)
                }
            }

            var loaded: [RecordingFile] = []
            for await item in group {
                if let item {
                    loaded.append(item)
                }
            }
            return loaded
        }

        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}

