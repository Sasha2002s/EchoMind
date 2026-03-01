//
//  SettingsViewModel.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("settings.whisperModelDownloaded") private(set) var whisperModelDownloaded: Bool = false

    @Published var whisperIsDownloading: Bool = false
    @Published var whisperDownloadProgress: Double? = nil
    @Published var whisperDownloadError: String? = nil
    @Published var whisperModelInstalledOnDisk: Bool = false

    private let whisperModelManager: WhisperModelManager
    private let whisperBackgroundDownloadManager: WhisperBackgroundDownloadManager
    private var cancellables = Set<AnyCancellable>()
    private var currentWhisperModelSelection: WhisperModelChoice = .none

    init(
        whisperModelManager: WhisperModelManager,
        whisperBackgroundDownloadManager: WhisperBackgroundDownloadManager
    ) {
        // Why: constructor injection keeps service wiring out of the view layer.
        self.whisperModelManager = whisperModelManager
        self.whisperBackgroundDownloadManager = whisperBackgroundDownloadManager
        bindBackgroundDownloadState()
        whisperBackgroundDownloadManager.restoreIfNeeded()
    }

    var whisperModelReady: Bool {
        whisperModelDownloaded || whisperModelInstalledOnDisk
    }

    func refreshWhisperModelInstalledState(for model: WhisperModelChoice) {
        currentWhisperModelSelection = model

        guard model != .none else {
            whisperModelInstalledOnDisk = false
            whisperModelDownloaded = false
            whisperDownloadError = nil
            return
        }

        let installed = whisperModelManager.isModelInstalled(for: model)
        whisperModelInstalledOnDisk = installed

        // Keep persisted flag aligned with real disk state to avoid stale UI state.
        if whisperModelDownloaded != installed {
            whisperModelDownloaded = installed
        }

        if installed {
            whisperDownloadError = nil
        }

        // Why: keep UI synced when user opens Settings while a background download is already active.
        if whisperBackgroundDownloadManager.activeModel == model {
            applyBackgroundDownloadState(
                status: whisperBackgroundDownloadManager.status,
                progress: whisperBackgroundDownloadManager.progress,
                activeModel: model
            )
        }
    }

    func startWhisperDownload(for model: WhisperModelChoice) {
        guard model != .none else { return }
        currentWhisperModelSelection = model
        refreshWhisperModelInstalledState(for: model)
        guard !whisperModelReady else { return }
        guard !whisperBackgroundDownloadManager.isBusy else { return }

        whisperDownloadError = nil
        whisperBackgroundDownloadManager.startDownload(for: model)
    }

    func cancelWhisperDownload() {
        whisperBackgroundDownloadManager.cancelDownload()
        whisperIsDownloading = false
        whisperDownloadProgress = nil
        whisperDownloadError = nil
    }

    func deleteWhisperModel(for model: WhisperModelChoice) {
        currentWhisperModelSelection = model
        whisperBackgroundDownloadManager.cancelDownload()
        whisperDownloadError = nil
        whisperModelManager.deleteModel(for: model)
        whisperModelDownloaded = false
        whisperModelInstalledOnDisk = false
        refreshWhisperModelInstalledState(for: model)
    }

    private func bindBackgroundDownloadState() {
        Publishers.CombineLatest3(
            whisperBackgroundDownloadManager.$status,
            whisperBackgroundDownloadManager.$progress,
            whisperBackgroundDownloadManager.$activeModel
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status, progress, activeModel in
            self?.applyBackgroundDownloadState(status: status, progress: progress, activeModel: activeModel)
        }
        .store(in: &cancellables)
    }

    private func applyBackgroundDownloadState(
        status: WhisperBackgroundDownloadManager.Status,
        progress: Double?,
        activeModel: WhisperModelChoice
    ) {
        switch status {
        case .idle:
            whisperIsDownloading = false
            whisperDownloadProgress = nil

        case .preparing:
            whisperIsDownloading = true
            whisperDownloadProgress = nil
            whisperDownloadError = nil

        case .downloading:
            whisperIsDownloading = true
            whisperDownloadProgress = progress
            whisperDownloadError = nil

        case .installing:
            whisperIsDownloading = true
            whisperDownloadProgress = nil
            whisperDownloadError = nil

        case .finished:
            whisperIsDownloading = false
            whisperDownloadProgress = nil
            whisperDownloadError = nil

            let modelToRefresh = activeModel == .none ? currentWhisperModelSelection : activeModel
            if modelToRefresh != .none {
                let installed = whisperModelManager.isModelInstalled(for: modelToRefresh)
                whisperModelInstalledOnDisk = installed
                whisperModelDownloaded = installed
            }

        case .failed(let message):
            whisperIsDownloading = false
            whisperDownloadProgress = nil
            whisperDownloadError = "Download/install failed: \(message)"

            let modelToRefresh = activeModel == .none ? currentWhisperModelSelection : activeModel
            if modelToRefresh != .none {
                let installed = whisperModelManager.isModelInstalled(for: modelToRefresh)
                whisperModelInstalledOnDisk = installed
                whisperModelDownloaded = installed
            } else {
                whisperModelInstalledOnDisk = false
                whisperModelDownloaded = false
            }
        }
    }
}
