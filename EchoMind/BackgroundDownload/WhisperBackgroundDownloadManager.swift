//
//  WhisperBackgroundDownloadManager.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import Foundation
import Combine

final class WhisperBackgroundDownloadManager: NSObject, ObservableObject {
    static let shared = WhisperBackgroundDownloadManager()
    static let sessionIdentifier = "com.oleksandrstepanov.echomind.whisper-model-download.v1"

    enum Status: Equatable {
        case idle
        case preparing
        case downloading
        case installing
        case finished
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var progress: Double? = nil
    @Published private(set) var activeModel: WhisperModelChoice = .none

    private struct PersistedDownloadContext: Codable {
        let modelRawValue: String
        let localArchiveFileName: String
        let expectedChecksum: String

        var model: WhisperModelChoice? {
            WhisperModelChoice(rawValue: modelRawValue)
        }
    }

    private let whisperModelManager: WhisperModelManager
    private let defaults: UserDefaults
    private let contextStorageKey = "whisper.background-download.context.v1"

    private var downloadTask: URLSessionDownloadTask?
    private var descriptorResolveTask: Task<Void, Never>?
    private var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(
        whisperModelManager: WhisperModelManager = WhisperModelManager(),
        defaults: UserDefaults = .standard
    ) {
        self.whisperModelManager = whisperModelManager
        self.defaults = defaults
        super.init()
    }

    var isBusy: Bool {
        switch status {
        case .preparing, .downloading, .installing:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    func startDownload(for model: WhisperModelChoice) {
        guard model != .none else { return }
        guard !isBusy else { return }

        descriptorResolveTask?.cancel()

        DispatchQueue.main.async {
            self.status = .preparing
            self.progress = nil
            self.activeModel = model
        }

        descriptorResolveTask = Task { [weak self] in
            guard let self else { return }

            do {
                let descriptor = try await self.whisperModelManager.resolveDownloadDescriptor(for: model)
                try Task.checkCancellation()

                self.savePersistedContext(
                    PersistedDownloadContext(
                        modelRawValue: descriptor.model.rawValue,
                        localArchiveFileName: descriptor.localArchiveFileName,
                        expectedChecksum: descriptor.expectedChecksum
                    )
                )

                await MainActor.run {
                    let task = self.session.downloadTask(with: descriptor.zipURL)
                    self.downloadTask = task
                    self.status = .downloading
                    self.progress = 0
                    self.activeModel = model
                    task.resume()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.status = .idle
                    self.progress = nil
                    self.activeModel = .none
                }
            } catch {
                self.clearPersistedContext()
                await MainActor.run {
                    self.downloadTask = nil
                    self.status = .failed(error.localizedDescription)
                    self.progress = nil
                    self.activeModel = model
                }
            }
        }
    }

    func cancelDownload() {
        descriptorResolveTask?.cancel()
        descriptorResolveTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        clearPersistedContext()

        DispatchQueue.main.async {
            self.status = .idle
            self.progress = nil
            self.activeModel = .none
        }
    }

    func restoreIfNeeded() {
        _ = session

        session.getAllTasks { [weak self] tasks in
            guard let self else { return }

            let activeDownloadTask = tasks.compactMap { $0 as? URLSessionDownloadTask }.first
            let persisted = self.loadPersistedContext()

            DispatchQueue.main.async {
                self.downloadTask = activeDownloadTask

                if let activeDownloadTask {
                    self.status = .downloading
                    if let persisted, let model = persisted.model {
                        self.activeModel = model
                    }
                    if activeDownloadTask.countOfBytesExpectedToReceive > 0 {
                        let value = Double(activeDownloadTask.countOfBytesReceived)
                            / Double(activeDownloadTask.countOfBytesExpectedToReceive)
                        self.progress = min(1.0, max(0.0, value))
                    } else {
                        self.progress = nil
                    }
                } else if let persisted, let model = persisted.model,
                          self.whisperModelManager.isModelInstalled(for: model) {
                    self.status = .finished
                    self.progress = 1
                    self.activeModel = model
                    self.clearPersistedContext()
                } else {
                    self.status = .idle
                    self.progress = nil
                    self.activeModel = .none
                    self.clearPersistedContext()
                }

                if activeDownloadTask == nil {
                    self.finishBackgroundEventsIfNeeded()
                }
            }
        }
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    func handleBackgroundEvents(
        for sessionIdentifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard sessionIdentifier == Self.sessionIdentifier else {
            completionHandler()
            return
        }

        setBackgroundCompletionHandler(completionHandler)
        restoreIfNeeded()
    }

    private func savePersistedContext(_ context: PersistedDownloadContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        defaults.set(data, forKey: contextStorageKey)
    }

    private func loadPersistedContext() -> PersistedDownloadContext? {
        guard let data = defaults.data(forKey: contextStorageKey),
              let decoded = try? JSONDecoder().decode(PersistedDownloadContext.self, from: data),
              decoded.model != nil else {
            return nil
        }
        return decoded
    }

    private func clearPersistedContext() {
        defaults.removeObject(forKey: contextStorageKey)
    }

    private func finishBackgroundEventsIfNeeded() {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

extension WhisperBackgroundDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.status = .downloading
            self.progress = min(1.0, max(0.0, value))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let persisted = loadPersistedContext(), let model = persisted.model else {
            DispatchQueue.main.async {
                self.downloadTask = nil
                self.status = .failed("Background download context is missing.")
                self.progress = nil
                self.activeModel = .none
            }
            finishBackgroundEventsIfNeeded()
            return
        }

        do {
            let archiveURL = try whisperModelManager.moveDownloadedArchive(
                fromTemporaryLocation: location,
                toLocalArchiveNamed: persisted.localArchiveFileName
            )

            DispatchQueue.main.async {
                self.status = .installing
                self.progress = 1
                self.activeModel = model
            }

            try whisperModelManager.installModel(
                for: model,
                fromArchiveAt: archiveURL,
                expectedChecksum: persisted.expectedChecksum
            )

            clearPersistedContext()
            DispatchQueue.main.async {
                self.downloadTask = nil
                self.status = .finished
                self.progress = 1
                self.activeModel = model
            }
        } catch {
            clearPersistedContext()
            DispatchQueue.main.async {
                self.downloadTask = nil
                self.status = .failed(error.localizedDescription)
                self.progress = nil
                self.activeModel = model
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        let nsError = error as NSError
        let isCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled

        if !isCancelled {
            clearPersistedContext()
        }

        DispatchQueue.main.async {
            self.downloadTask = nil
            self.progress = nil

            if isCancelled {
                self.status = .idle
                self.activeModel = .none
            } else {
                self.status = .failed(error.localizedDescription)
            }
        }

        finishBackgroundEventsIfNeeded()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        finishBackgroundEventsIfNeeded()
    }
}
