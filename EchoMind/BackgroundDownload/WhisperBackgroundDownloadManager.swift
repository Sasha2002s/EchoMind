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
    static let wifiOnlySettingKey = "settings.whisperDownloadWiFiOnly"
    static let pauseOnLowPowerSettingKey = "settings.whisperPauseOnLowPowerMode"

    enum Status: Equatable {
        case idle
        case preparing
        case downloading
        case pausedLowPower
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
    private var lowPowerObserver: NSObjectProtocol?
    private var resumeData: Data?
    private var isPausingForLowPowerMode = false

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
        registerLowPowerObserver()
    }

    deinit {
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
    }

    var isBusy: Bool {
        switch status {
        case .preparing, .downloading, .pausedLowPower, .installing:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    func startDownload(for model: WhisperModelChoice) {
        guard model != .none else { return }

        if status == .pausedLowPower, activeModel == model {
            resumeDownloadAfterLowPowerIfPossible()
            return
        }

        guard !isBusy else { return }

        if shouldPauseForLowPowerMode {
            DispatchQueue.main.async {
                self.status = .pausedLowPower
                self.activeModel = model
            }
            return
        }

        prepareAndStartDownload(for: model)
    }

    private func prepareAndStartDownload(for model: WhisperModelChoice) {
        guard model != .none else { return }

        descriptorResolveTask?.cancel()
        descriptorResolveTask = nil

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
                    let request = self.makeDownloadRequest(url: descriptor.zipURL)
                    let task = self.session.downloadTask(with: request)
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
                    self.resumeData = nil
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
        isPausingForLowPowerMode = false
        downloadTask?.cancel()
        downloadTask = nil
        resumeData = nil
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

    private func registerLowPowerObserver() {
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLowPowerStateChanged()
        }
    }

    private func handleLowPowerStateChanged() {
        guard pauseOnLowPowerModeEnabled else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            if status == .downloading {
                pauseDownloadForLowPowerMode()
            }
        } else if status == .pausedLowPower {
            resumeDownloadAfterLowPowerIfPossible()
        }
    }

    private func pauseDownloadForLowPowerMode() {
        guard let task = downloadTask else { return }
        isPausingForLowPowerMode = true

        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self else { return }

            DispatchQueue.main.async {
                self.resumeData = data
                self.downloadTask = nil
                self.status = .pausedLowPower
            }
        })
    }

    private func resumeDownloadAfterLowPowerIfPossible() {
        guard status == .pausedLowPower else { return }
        guard !shouldPauseForLowPowerMode else { return }
        guard activeModel != .none else { return }

        if let resumeData {
            let task = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
            downloadTask = task
            status = .downloading
            task.resume()
            return
        }

        prepareAndStartDownload(for: activeModel)
    }

    private var wifiOnlyEnabled: Bool {
        defaults.object(forKey: Self.wifiOnlySettingKey) as? Bool ?? true
    }

    private var pauseOnLowPowerModeEnabled: Bool {
        defaults.object(forKey: Self.pauseOnLowPowerSettingKey) as? Bool ?? true
    }

    private var shouldPauseForLowPowerMode: Bool {
        pauseOnLowPowerModeEnabled && ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func makeDownloadRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = !wifiOnlyEnabled
        request.allowsExpensiveNetworkAccess = !wifiOnlyEnabled
        request.allowsConstrainedNetworkAccess = !wifiOnlyEnabled
        return request
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

            if isCancelled && self.isPausingForLowPowerMode {
                self.isPausingForLowPowerMode = false
                self.status = .pausedLowPower
                if self.activeModel == .none, let persisted = self.loadPersistedContext()?.model {
                    self.activeModel = persisted
                }
            } else if isCancelled {
                self.resumeData = nil
                self.status = .idle
                self.progress = nil
                self.activeModel = .none
            } else {
                self.resumeData = nil
                self.status = .failed(error.localizedDescription)
                self.progress = nil
            }
        }

        finishBackgroundEventsIfNeeded()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        finishBackgroundEventsIfNeeded()
    }
}
