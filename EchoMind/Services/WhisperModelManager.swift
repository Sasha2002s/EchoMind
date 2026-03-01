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
    nonisolated init() {}

    private struct ExpectedItemGroup {
        let alternatives: [String]
    }

    private struct ModelArchiveSource {
        let zipURL: URL
        let checksumURL: URL
        let localArchiveFileName: String
        let expectedChecksum: String
    }

    struct WhisperModelDownloadDescriptor {
        let model: WhisperModelChoice
        let zipURL: URL
        let localArchiveFileName: String
        let expectedChecksum: String
    }

    func isModelInstalled(for model: WhisperModelChoice) -> Bool {
        guard model != .none else { return false }
        return isModelInstalled(at: modelFolder(for: model))
    }

    func installedModelFolderPath(for model: WhisperModelChoice) -> String? {
        guard model != .none else { return nil }
        let folder = modelFolder(for: model)
        guard isModelInstalled(at: folder) else { return nil }
        return folder.path
    }

    func deleteModel(for model: WhisperModelChoice) {
        guard model != .none else { return }
        let folder = modelFolder(for: model)
        let root = modelRootFolder()

        try? FileManager.default.removeItem(at: folder)

        // Why: clean both legacy and model-specific temp archives/checksums.
        for archiveName in archiveFileNameCandidates(for: model) {
            let archiveURL = root.appendingPathComponent(archiveName)
            let checksumURL = root.appendingPathComponent("\(archiveName).sha256")
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: checksumURL)
        }
    }

    func downloadModel(
        for model: WhisperModelChoice,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        guard model != .none else { return }

        let fm = FileManager.default
        let descriptor = try await resolveDownloadDescriptor(for: model)
        let zipDestination = localArchiveURL(fileName: descriptor.localArchiveFileName)
        let zipURL = descriptor.zipURL
        let expectedChecksum = descriptor.expectedChecksum

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

        try installVerifiedArchive(for: model, fromArchiveAt: zipDestination)
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

    func localArchiveURL(fileName: String) -> URL {
        modelRootFolder().appendingPathComponent(fileName)
    }

    func moveDownloadedArchive(
        fromTemporaryLocation tempLocation: URL,
        toLocalArchiveNamed fileName: String
    ) throws -> URL {
        let fm = FileManager.default
        let destination = localArchiveURL(fileName: fileName)

        if fm.fileExists(atPath: destination.path) {
            // Why: background downloads replace previous partial/older archives.
            try fm.removeItem(at: destination)
        }

        try fm.moveItem(at: tempLocation, to: destination)
        return destination
    }

    private func modelBaseURL() throws -> URL {
        let base = "https://pub-fd248852a2764fb0b71b284a4f678c9f.r2.dev"
        guard let url = URL(string: base) else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model base URL configuration."]
            )
        }
        return url
    }

    private func modelAssetURL(named fileName: String) throws -> URL {
        let base = try modelBaseURL()
        guard let url = URL(string: fileName, relativeTo: base)?.absoluteURL else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model asset URL for \(fileName)."]
            )
        }
        return url
    }

    private func archiveFileNameCandidates(for model: WhisperModelChoice) -> [String] {
        // Why: prefer model-specific artifact naming, keep legacy fallback for compatibility.
        let candidates = [
            "\(model.folderName).zip",
            "\(model.folderName).ZIP",
            "whisper_model.zip",
            "whisper-model.zip"
        ]
        return uniquePreservingOrder(candidates)
    }

    private func checksumFileNameCandidates(forArchiveName archiveName: String) -> [String] {
        let candidates = [
            "\(archiveName).sha256",
            "\(archiveName).SHA256",
            "\(archiveName).sha-256",
            "\(archiveName).SHA-256",
            "whisper_model.zip.sha256"
        ]
        return uniquePreservingOrder(candidates)
    }

    func resolveDownloadDescriptor(for model: WhisperModelChoice) async throws -> WhisperModelDownloadDescriptor {
        guard model != .none else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "No local model selected for download."]
            )
        }

        let source = try await resolveModelArchiveSource(for: model)
        return WhisperModelDownloadDescriptor(
            model: model,
            zipURL: source.zipURL,
            localArchiveFileName: source.localArchiveFileName,
            expectedChecksum: source.expectedChecksum
        )
    }

    func installModel(
        for model: WhisperModelChoice,
        fromArchiveAt archiveURL: URL,
        expectedChecksum: String
    ) throws {
        guard model != .none else { return }

        let actualChecksum = try sha256HexDigest(of: archiveURL)
        guard actualChecksum == expectedChecksum else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Model checksum verification failed. Downloaded file does not match expected SHA-256."]
            )
        }

        try installVerifiedArchive(for: model, fromArchiveAt: archiveURL)
    }

    private func resolveModelArchiveSource(for model: WhisperModelChoice) async throws -> ModelArchiveSource {
        var attemptedArchives: [String] = []
        var attemptedChecksums: [String] = []

        for archiveName in archiveFileNameCandidates(for: model) {
            let archiveURL = try modelAssetURL(named: archiveName)
            attemptedArchives.append(archiveURL.absoluteString)

            guard try await remoteFileExists(at: archiveURL) else {
                continue
            }

            for checksumName in checksumFileNameCandidates(forArchiveName: archiveName) {
                let checksumURL = try modelAssetURL(named: checksumName)
                attemptedChecksums.append(checksumURL.absoluteString)

                guard try await remoteFileExists(at: checksumURL) else {
                    continue
                }

                let checksum = try await fetchExpectedChecksum(from: checksumURL)
                return ModelArchiveSource(
                    zipURL: archiveURL,
                    checksumURL: checksumURL,
                    localArchiveFileName: archiveName,
                    expectedChecksum: checksum
                )
            }
        }

        throw NSError(
            domain: "EchoMind.ModelInstall",
            code: 8,
            userInfo: [
                NSLocalizedDescriptionKey: """
                Could not locate model archive/checksum on the server.
                Tried archives: \(attemptedArchives.joined(separator: ", "))
                Tried checksums: \(attemptedChecksums.joined(separator: ", "))
                """
            ]
        )
    }

    private func remoteFileExists(at url: URL) async throws -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        switch http.statusCode {
        case 200...299:
            return true
        case 404:
            return false
        default:
            // Why: object storage/static hosts can return non-404 for HEAD (e.g. 403/405)
            // even when object exists; verify using a ranged GET probe before treating as missing.
            return try await remoteFileExistsUsingRangeRequest(at: url)
        }
    }

    private func remoteFileExistsUsingRangeRequest(at url: URL) async throws -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        switch http.statusCode {
        case 200, 206:
            return true
        case 404:
            return false
        default:
            return false
        }
    }

    private func fetchExpectedChecksum(from checksumURL: URL) async throws -> String {
        let request = URLRequest(
            url: checksumURL,
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

    private func sha256HexDigest(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 64 * 1024

        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hexString(from: hasher.finalize())
    }

    private func installVerifiedArchive(for model: WhisperModelChoice, fromArchiveAt archiveURL: URL) throws {
        let fm = FileManager.default
        let folder = modelFolder(for: model)

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let existingItems = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in existingItems {
            // Why: install must start from a clean destination to avoid stale model artifacts.
            try fm.removeItem(at: item)
        }

        try fm.unzipItem(at: archiveURL, to: folder)
        try normalizeUnzippedModelLayout(in: folder)

        guard isModelInstalled(at: folder) else {
            throw NSError(
                domain: "EchoMind.ModelInstall",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unzipped, but expected model files were not found. Ensure the zip includes AudioEncoder/TextDecoder/MelSpectrogram (.mlmodelc or .mlmodel) plus config.json and generation_config.json."]
            )
        }
    }

    private func expectedModelItemGroups() -> [ExpectedItemGroup] {
        [
            // Why: accept both common naming variants found in Whisper export bundles.
            ExpectedItemGroup(alternatives: ["AudioEncoder.mlmodelc", "AudioEncoder.mlmodel", "audio_encoder.mlmodelc", "audio_encoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["TextDecoder.mlmodelc", "TextDecoder.mlmodel", "text_decoder.mlmodelc", "text_decoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["MelSpectrogram.mlmodelc", "MelSpectrogram.mlmodel", "mel_spectrogram.mlmodelc", "mel_spectrogram.mlmodel"]),
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

    private func findFolderContainingExpectedItems(startingAt root: URL, maxDepth: Int = 8) -> URL? {
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

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }
        return ordered
    }
}
