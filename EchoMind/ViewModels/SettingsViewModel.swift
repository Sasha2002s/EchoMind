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
    private var whisperDownloadTask: Task<Void, Never>? = nil

    init(whisperModelManager: WhisperModelManager) {
        // Why: constructor injection keeps service wiring out of the view layer.
        self.whisperModelManager = whisperModelManager
    }

    var whisperModelReady: Bool {
        whisperModelDownloaded || whisperModelInstalledOnDisk
    }

    func refreshWhisperModelInstalledState(for model: WhisperModelChoice) {
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
    }

    func startWhisperDownload(for model: WhisperModelChoice) {
        guard model != .none else { return }
        refreshWhisperModelInstalledState(for: model)
        guard !whisperModelReady else { return }
        guard !whisperIsDownloading else { return }

        whisperDownloadTask?.cancel()
        whisperDownloadTask = Task {
            await downloadWhisperModelIfNeeded(for: model)
        }
    }

    func cancelWhisperDownload() {
        whisperDownloadTask?.cancel()
        whisperDownloadTask = nil
        whisperIsDownloading = false
        whisperDownloadProgress = nil
    }

    func deleteWhisperModel(for model: WhisperModelChoice) {
        whisperDownloadError = nil
        whisperModelManager.deleteModel(for: model)
        whisperModelDownloaded = false
        whisperModelInstalledOnDisk = false
        refreshWhisperModelInstalledState(for: model)
    }

    private func downloadWhisperModelIfNeeded(for model: WhisperModelChoice) async {
        whisperDownloadError = nil
        whisperDownloadProgress = nil
        whisperIsDownloading = true
        defer {
            whisperIsDownloading = false
            whisperDownloadProgress = nil
            whisperDownloadTask = nil
        }

        do {
            try await whisperModelManager.downloadModel(for: model) { progress in
                await MainActor.run {
                    self.whisperDownloadProgress = progress
                }
            }

            whisperModelDownloaded = true
            whisperModelInstalledOnDisk = true
            whisperDownloadError = nil
        } catch is CancellationError {
            whisperDownloadError = nil
            whisperModelDownloaded = false
            whisperModelInstalledOnDisk = false
            whisperDownloadProgress = nil
        } catch {
            whisperModelDownloaded = false
            whisperModelInstalledOnDisk = false
            whisperDownloadProgress = nil
            whisperDownloadError = "Download/install failed: \(error.localizedDescription)"
        }
    }
}
