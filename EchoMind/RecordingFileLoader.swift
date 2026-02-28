//
//  RecordingFileLoader.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import Foundation
import AVFoundation

// MARK: - Loader



enum RecordingFileLoader {
    static func loadRecordingsFromDocuments() async -> [RecordingFile] {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

    // We record as "recording_<ISO8601>.m4a".
    // Also include any other .m4a you might add later.
    let urls: [URL]
    do {
        urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey],
            options: [.skipsHiddenFiles]
        )
    } catch {
        return []
    }

    let m4a = urls.filter { $0.pathExtension.lowercased() == "m4a" }

    // Load durations asynchronously for each file
    let items: [RecordingFile] = await withTaskGroup(of: RecordingFile?.self) { group in
        for url in m4a {
            group.addTask {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey])
                let created = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
                let resourceID = values?.fileResourceIdentifier
                let stableID = resourceID.map { String(describing: $0) } ?? url.lastPathComponent

                let duration = await audioDuration(url: url)
                return RecordingFile(
                    id: stableID,
                    url: url,
                    createdAt: created,
                    duration: duration
                )
            }
        }

        var results: [RecordingFile] = []
        for await item in group {
            if let item { results.append(item) }
        }
        return results
    }

    // Newest first
    return items.sorted { $0.createdAt > $1.createdAt }
    }

    private static func audioDuration(url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
    }
}
