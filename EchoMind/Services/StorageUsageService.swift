//
//  StorageUsageService.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation

struct StorageUsageSnapshot {
    let audioBytes: Int64
    let textBytes: Int64
    let modelBytes: Int64
    let modelItems: [StorageUsageModelItem]

    var totalBytes: Int64 {
        audioBytes + textBytes + modelBytes
    }

    static let empty = StorageUsageSnapshot(
        audioBytes: 0,
        textBytes: 0,
        modelBytes: 0,
        modelItems: []
    )
}

struct StorageUsageModelItem: Identifiable {
    let id: String
    let name: String
    let bytes: Int64
}

struct StorageUsageService {
    func loadSnapshot() -> StorageUsageSnapshot {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let audioBytes = sizeOfAudioFiles(in: documentsDirectory)
        let textBytes = sizeOfTextSidecars(in: documentsDirectory)

        let modelRoot = modelRootDirectory()
        let modelItems = loadModelItems(in: modelRoot)
        let modelBytes = modelItems.reduce(0) { $0 + $1.bytes }

        return StorageUsageSnapshot(
            audioBytes: audioBytes,
            textBytes: textBytes,
            modelBytes: modelBytes,
            modelItems: modelItems.sorted { $0.bytes > $1.bytes }
        )
    }

    private func sizeOfAudioFiles(in directory: URL?) -> Int64 {
        let audioExtensions: Set<String> = [
            "m4a", "mp3", "wav", "aac", "caf", "aif", "aiff", "flac", "m4b"
        ]

        return totalSize(in: directory) { url in
            audioExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private func sizeOfTextSidecars(in directory: URL?) -> Int64 {
        totalSize(in: directory) { url in
            url.pathExtension.lowercased() == "txt"
        }
    }

    private func modelRootDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("EchoMind", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func loadModelItems(in root: URL) -> [StorageUsageModelItem] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return items.map { itemURL in
            let rawName = itemURL.lastPathComponent
            let bytes = recursiveItemSize(at: itemURL)
            return StorageUsageModelItem(
                id: rawName,
                name: displayNameForModelItem(rawName),
                bytes: bytes
            )
        }
    }

    private func displayNameForModelItem(_ rawName: String) -> String {
        for choice in WhisperModelChoice.allCases where choice != .none {
            if choice.folderName == rawName {
                return "Whisper \(choice.displayName)"
            }
        }
        return rawName
    }

    private func totalSize(in directory: URL?, includeFile: (URL) -> Bool) -> Int64 {
        guard let directory else { return 0 }

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            guard includeFile(fileURL) else { continue }
            total += fileSize(at: fileURL)
        }

        return total
    }

    private func recursiveItemSize(at url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { return 0 }

        if !isDirectory.boolValue {
            return fileSize(at: url)
        }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            total += fileSize(at: fileURL)
        }

        return total
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}

