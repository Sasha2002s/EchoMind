//
//  RecentRecordingService.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import AVFoundation

enum RecentRecordingService {
    static func loadRecent(limit: Int) -> [RecordingFile] {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let m4a = urls.filter { $0.pathExtension.lowercased() == "m4a" }

        let items: [RecordingFile] = m4a.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let created = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
            let safeDuration: TimeInterval = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0

            return RecordingFile(
                id: url.lastPathComponent,
                url: url,
                createdAt: created,
                duration: safeDuration
            )
        }

        return items
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
