//
//  AudioRecorderViewModel.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//


import Foundation
import Combine
import AVFoundation

// MARK: - ViewModel

@MainActor
final class AudioRecorderViewModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var duration: TimeInterval = 0
    @Published var statusText: String = ""
    @Published var waveformLevels: [CGFloat] = Array(repeating: 0.1, count: 24)
    @Published var showMicAlert: Bool = false

    private var recorder: AVAudioRecorder?
    private var durationTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

    private(set) var recordedURL: URL?

    var formattedDuration: String {
        let total = Int(duration.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var primaryActionDisabled: Bool {
        // Don’t allow finishing immediately by accident.
        isRecording && duration < 0.4
    }

    func onAppear() {
        statusText = "Tap Start and speak clearly."
    }

    func onDisappear() {
        stopTimers()
        recorder?.stop()
        recorder = nil
    }

    func startRecording() {
        Task {
            let ok = await requestMicPermissionIfNeeded()
            guard ok else {
                showMicAlert = true
                statusText = "Microphone access is disabled."
                return
            }

            do {
                try configureAudioSession()
                let url = makeNewRecordingURL()

                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]

                let newRecorder = try AVAudioRecorder(url: url, settings: settings)
                newRecorder.isMeteringEnabled = true
                newRecorder.prepareToRecord()
                newRecorder.record()

                recorder = newRecorder
                recordedURL = url

                isRecording = true
                duration = 0
                statusText = "Recording…"

                startTimers()
            } catch {
                statusText = "Failed to start recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        recorder?.stop()
        stopTimers()
        isRecording = false
        statusText = "Saved recording."

        // Optional: release session so other audio can resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelRecording() {
        recorder?.stop()
        stopTimers()
        isRecording = false
        statusText = "Cancelled."

        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Permissions

    private func requestMicPermissionIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    // MARK: - Timers & metering

    private func startTimers() {
        stopTimers()

        durationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                self.duration += 0.1
            }
        }

        levelTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 70_000_000) // 0.07s
                self.tickLevel()
            }
        }
    }

    private func stopTimers() {
        durationTask?.cancel()
        durationTask = nil
        levelTask?.cancel()
        levelTask = nil
    }

    private func tickLevel() {
        guard let recorder else { return }
        recorder.updateMeters()

        // averagePower is in dB, typically [-160, 0]
        let db = recorder.averagePower(forChannel: 0)
        let normalized = normalizePower(db)

        // Push into levels ring buffer
        waveformLevels.removeFirst()
        waveformLevels.append(max(0.06, normalized))
    }

    private func normalizePower(_ db: Float) -> CGFloat {
        // Convert dB to a 0...1-ish level.
        // -60 dB ~ silence; 0 dB ~ loud.
        let minDb: Float = -60
        let clamped = max(minDb, db)
        let value = (clamped - minDb) / abs(minDb) // 0...1
        // Add a gentle curve so quiet speech still shows.
        let curved = pow(value, 0.5)
        return CGFloat(curved)
    }

    // MARK: - File URL

    private func makeNewRecordingURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let name = "recording_\(formatter.string(from: Date())).m4a"
        return dir.appendingPathComponent(name)
    }
}
