//
//  WhisperModelManager.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import ZIPFoundation
import CryptoKit

struct WhisperModelManager {
    private struct ExpectedItemGroup {
        let alternatives: [String]
    }

    func isModelInstalled(for model: WhisperModelChoice) -> Bool {
        guard model != .none else { return false }
        return isModelInstalled(at: modelFolder(for: model))
    }

    func deleteModel(for model: WhisperModelChoice) {
        guard model != .none else { return }
        let folder = modelFolder(for: model)
        let zip = modelRootFolder().appendingPathComponent("whisper_model.zip")

        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: zip)
    }

    func downloadModel(
        for model: WhisperModelChoice,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        guard model != .none else { return }

        let fm = FileManager.default
        let folder = modelFolder(for: model)
        let zipDestination = modelRootFolder().appendingPathComponent("whisper_model.zip")
        let zipURL = try modelZipURL()
        let expectedChecksum = try await fetchExpectedChecksum()

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let request = URLRequest(url: zipURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let expectedLength = response.expectedContentLength
        var received: Int64 = 0
        var hasher = SHA256()

        if fm.fileExists(atPath: zipDestination.path) {
            try fm.removeItem(at: zipDestination)
        }
        _ = fm.createFile(atPath: zipDestination.path, contents: nil)

        let handle = try FileHandle(forWritingTo: zipDestination)
        defer { try? handle.close() }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if buffer.count >= 64 * 1024 {
                let data = Data(buffer)
                try handle.write(contentsOf: data)
                hasher.update(data: data)
                received += Int64(data.count)
                buffer.removeAll(keepingCapacity: true)
                await progress(progressValue(received: received, expectedLength: expectedLength))
            }
        }

        if !buffer.isEmpty {
            let data = Data(buffer)
            try handle.write(contentsOf: data)
            hasher.update(data: data)
            received += Int64(data.count)
            buffer.removeAll(keepingCapacity: false)
            await progress(progressValue(received: received, expectedLength: expectedLength))
        }

        if expectedLength > 0 {
            await progress(1.0)
        }

        // Why: do not install unverified model bytes.
        let actualChecksum = hexString(from: hasher.finalize())
        guard actualChecksum == expectedChecksum else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Model checksum verification failed. Downloaded file does not match expected SHA-256."]
            )
        }

        if fm.fileExists(atPath: folder.path) {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                try? fm.removeItem(at: item)
            }
        }

        try fm.unzipItem(at: zipDestination, to: folder)
        try normalizeUnzippedModelLayout(in: folder)

        guard isModelInstalled(at: folder) else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unzipped, but expected model files were not found. Ensure the zip includes AudioEncoder/TextDecoder/MelSpectrogram (.mlmodelc or .mlmodel) plus config.json and generation_config.json."]
            )
        }
    }

    private func modelRootFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base
            .appendingPathComponent("EchoMind", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func modelFolder(for model: WhisperModelChoice) -> URL {
        modelRootFolder().appendingPathComponent(model.folderName, isDirectory: true)
    }

    private func modelZipURL() throws -> URL {
        let base = "https://pub-fd248852a2764fb0b71b284a4f678c9f.r2.dev"
        guard let url = URL(string: base + "/whisper_model.zip") else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model download URL configuration."]
            )
        }
        return url
    }

    private func modelChecksumURL() throws -> URL {
        let base = "https://pub-fd248852a2764fb0b71b284a4f678c9f.r2.dev"
        guard let url = URL(string: base + "/whisper_model.zip.sha256") else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model checksum URL configuration."]
            )
        }
        return url
    }

    private func fetchExpectedChecksum() async throws -> String {
        let request = URLRequest(
            url: try modelChecksumURL(),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Could not fetch model checksum (HTTP \(http.statusCode))."]
            )
        }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Checksum file is not valid UTF-8 text."]
            )
        }

        let token = raw
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .first(where: { !$0.isEmpty }) ?? ""

        let isValid = token.count == 64 && token.allSatisfy(\.isHexDigit)
        guard isValid else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Checksum file does not contain a valid SHA-256 hash."]
            )
        }

        return token
    }

    private func hexString(from digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private func expectedModelItemGroups() -> [ExpectedItemGroup] {
        [
            ExpectedItemGroup(alternatives: ["AudioEncoder.mlmodelc", "AudioEncoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["TextDecoder.mlmodelc", "TextDecoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["MelSpectrogram.mlmodelc", "MelSpectrogram.mlmodel"]),
            ExpectedItemGroup(alternatives: ["config.json"]),
            ExpectedItemGroup(alternatives: ["generation_config.json"])
        ]
    }

    private func isModelInstalled(at folder: URL) -> Bool {
        let fm = FileManager.default
        return expectedModelItemGroups().allSatisfy { group in
            group.alternatives.contains { name in
                fm.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
        }
    }

    private func findFolderContainingExpectedItems(startingAt root: URL, maxDepth: Int = 4) -> URL? {
        let fm = FileManager.default

        func isIgnorableFolderName(_ name: String) -> Bool {
            name.hasPrefix("__MACOSX") || name.hasPrefix(".")
        }

        func search(_ folder: URL, depth: Int) -> URL? {
            if isModelInstalled(at: folder) {
                return folder
            }
            guard depth < maxDepth else { return nil }

            let children = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children {
                guard let isDir = try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true else {
                    continue
                }
                if isIgnorableFolderName(child.lastPathComponent) { continue }
                if let found = search(child, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }

        return search(root, depth: 0)
    }

    private func normalizeUnzippedModelLayout(in destinationFolder: URL) throws {
        let fm = FileManager.default

        if isModelInstalled(at: destinationFolder) {
            return
        }

        guard let installRoot = findFolderContainingExpectedItems(startingAt: destinationFolder) else {
            return
        }

        if installRoot != destinationFolder {
            let items = try fm.contentsOfDirectory(at: installRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for item in items {
                let destination = destinationFolder.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    try? fm.removeItem(at: destination)
                }
                try fm.moveItem(at: item, to: destination)
            }

            try? fm.removeItem(at: installRoot)
        }

        let macOSXFolder = destinationFolder.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macOSXFolder.path) {
            try? fm.removeItem(at: macOSXFolder)
        }
    }

    private func progressValue(received: Int64, expectedLength: Int64) -> Double? {
        guard expectedLength > 0 else { return nil }
        return min(1.0, max(0.0, Double(received) / Double(expectedLength)))
    }
}
