//
//  SettingsWhisperSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsWhisperSection: View {
    @Binding var whisperModel: WhisperModelChoice
    @ObservedObject var vm: SettingsViewModel
    @State private var showStopConfirmation = false

    var body: some View {
        Section("Local Whisper") {
            PickerRow(
                title: "Whisper Model",
                subtitle: whisperModel.displayName,
                systemImage: "arrow.down.circle",
                selection: $whisperModel
            ) {
                ForEach(WhisperModelChoice.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }

            if whisperModel == .none {
                SettingsRow(
                    title: "Offline transcription",
                    subtitle: "Select a model to enable on-device Whisper",
                    systemImage: "waveform.badge.mic"
                )
            } else {
                let isReady = vm.whisperModelReady

                SettingsRow(
                    title: isReady ? "Model ready" : "Model not downloaded",
                    subtitle: isReady ? "Available offline" : "~450-600 MB download",
                    systemImage: isReady ? "checkmark.seal" : "icloud.and.arrow.down"
                )

                if let whisperDownloadError = vm.whisperDownloadError {
                    Text(whisperDownloadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if vm.whisperIsDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        if let progress = vm.whisperDownloadProgress {
                            ProgressView(value: progress)
                            Text("Downloading... \(Int(progress * 100))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                            Text("Preparing...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    if vm.whisperIsDownloading {
                        Button(role: .destructive) {
                            // Why: stopping a large model download by accident is expensive for users.
                            showStopConfirmation = true
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    } else {
                        if !isReady {
                            Button {
                                HapticsService.impact(.medium)
                                vm.startWhisperDownload(for: whisperModel)
                            } label: {
                                Label("Download", systemImage: "arrow.down")
                            }
                        }
                    }

                    Spacer()

                    if isReady && !vm.whisperIsDownloading {
                        Button(role: .destructive) {
                            HapticsService.notify(.warning)
                            vm.deleteWhisperModel(for: whisperModel)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Text("Whisper runs fully on device. Download once, then you can transcribe without internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: vm.whisperModelReady) { _, isReady in
            if isReady {
                HapticsService.notify(.success)
            }
        }
        .onChange(of: vm.whisperDownloadError) { _, newValue in
            if newValue != nil {
                HapticsService.notify(.error)
            }
        }
        .confirmationDialog(
            "Stop model download?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Downloading", role: .cancel) { }
            Button("Stop Download", role: .destructive) {
                HapticsService.notify(.warning)
                vm.cancelWhisperDownload()
            }
        } message: {
            Text("The current Whisper download will be canceled.")
        }
    }
}
