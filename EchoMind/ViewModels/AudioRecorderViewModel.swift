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
    private static let includeDevicePlaybackAudioSettingKey = "settings.includeDevicePlaybackAudio"

    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var duration: TimeInterval = 0
    @Published var statusText: String = ""
    @Published var waveformLevels: [CGFloat] = Array(repeating: 0.1, count: 24)
    @Published var showMicAlert: Bool = false

    private let defaults: UserDefaults
    private var recorder: AVAudioRecorder?
    private var durationTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private let liveActivityManager = EchoMindLiveActivityManager.shared
    private var lastPublishedElapsedSeconds: Int = -1
    private var interruptionObserver: NSObjectProtocol?
    private var wasInterruptedDuringRecording = false
    private var isStartingRecording = false

    private(set) var recordedURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerAudioSessionInterruptionObserver()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    var hasActiveSession: Bool {
        recordedURL != nil && (isRecording || isPaused)
    }

    var formattedDuration: String {
        let total = Int(duration.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var primaryActionDisabled: Bool {
        // Why: block repeat taps while async recording setup is still in-flight.
        if isStartingRecording { return true }
        // Don’t allow finishing immediately by accident.
        return (isRecording || isPaused) && duration < 0.4
    }

    func onAppear() {
        if hasActiveSession {
            // Why: allow reopening the recording UI without interrupting an in-progress capture.
            syncDurationFromRecorder()
            if isRecording {
                startTimers()
                statusText = "Recording…"
            } else {
                stopTimers()
                statusText = "Paused."
            }
            return
        }
        // Why: avoid showing stale bars from a previous session when opening the recorder idle.
        resetWaveformLevels()
        statusText = "Tap Start and speak clearly."
    }

    func onDisappear() {
        if hasActiveSession {
            // Why: keep duration updates visible in the floating control while hidden.
            stopMeteringUpdates()
            return
        }
        tearDownRecorderResources()
    }

    func startRecording() {
        // Why: Siri/tap retries can arrive before state flips to recording; prevent parallel recorder setup.
        guard !isStartingRecording, !hasActiveSession else { return }
        isStartingRecording = true

        Task { @MainActor in
            defer { isStartingRecording = false }

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

                // Why: ensure each new session starts with a clean waveform baseline.
                resetWaveformLevels()
                isRecording = true
                isPaused = false
                duration = 0
                statusText = "Recording…"

                startTimers()
                publishRecordingLiveActivity(force: true)
            } catch {
                statusText = "Failed to start recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    func finishRecording() {
        guard hasActiveSession else { return }
        syncDurationFromRecorder()
        let elapsedSeconds = max(0, Int(duration.rounded(.down)))
        recorder?.stop()
        stopTimers()
        isRecording = false
        isPaused = false
        statusText = "Saved recording."
        // Why: hide live waveform once capture is finished to prevent "still recording" confusion.
        resetWaveformLevels()
        lastPublishedElapsedSeconds = -1
        liveActivityManager.endRecording(elapsedSeconds: elapsedSeconds)

        // Optional: release session so other audio can resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelRecording() {
        syncDurationFromRecorder()
        let elapsedSeconds = max(0, Int(duration.rounded(.down)))
        recorder?.stop()
        stopTimers()
        isRecording = false
        isPaused = false
        statusText = "Cancelled."
        // Why: clear any last metering bars when user discards a take.
        resetWaveformLevels()
        lastPublishedElapsedSeconds = -1
        liveActivityManager.endRecording(elapsedSeconds: elapsedSeconds)

        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedURL = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func pauseRecording() {
        guard isRecording, let recorder else { return }
        recorder.pause()
        stopTimers()
        isRecording = false
        isPaused = true
        statusText = "Paused."
        publishRecordingLiveActivity(force: true)
    }

    func resumeRecording() {
        guard isPaused, let recorder else { return }
        recorder.record()
        isRecording = true
        isPaused = false
        statusText = "Recording…"
        startTimers()
        publishRecordingLiveActivity(force: true)
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
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        let mode: AVAudioSession.Mode

        if includeDevicePlaybackAudio {
            // Why: allow other media playback to continue while we still capture microphone input.
            options.insert(.mixWithOthers)
            mode = .default
        } else {
            mode = .spokenAudio
        }

        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setActive(true)
    }

    // MARK: - Timers & metering

    private func startTimers() {
        stopTimers()

        durationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                self.syncDurationFromRecorder()
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
        stopMeteringUpdates()
    }

    private func stopMeteringUpdates() {
        levelTask?.cancel()
        levelTask = nil
    }

    private func tearDownRecorderResources() {
        stopTimers()
        recorder?.stop()
        recorder = nil
        isPaused = false
        isRecording = false
    }

    private func syncDurationFromRecorder() {
        guard let recorder else { return }
        duration = recorder.currentTime
        publishRecordingLiveActivity()
    }

    private func publishRecordingLiveActivity(force: Bool = false) {
        guard hasActiveSession else { return }

        let elapsedSeconds = max(0, Int(duration.rounded(.down)))
        guard force || elapsedSeconds != lastPublishedElapsedSeconds else { return }

        lastPublishedElapsedSeconds = elapsedSeconds
        liveActivityManager.upsertRecording(
            isPaused: isPaused,
            elapsedSeconds: elapsedSeconds
        )
    }

    private var includeDevicePlaybackAudio: Bool {
        defaults.object(forKey: Self.includeDevicePlaybackAudioSettingKey) as? Bool ?? false
    }

    private func registerAudioSessionInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let typeRawValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRawValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0

            // Why: capture only primitive values so the Task closure stays Sendable-safe in Swift 6 mode.
            Task { @MainActor [weak self] in
                guard let typeRawValue else { return }
                self?.handleAudioSessionInterruption(typeRawValue: typeRawValue, optionsRawValue: optionsRawValue)
            }
        }
    }

    private func handleAudioSessionInterruption(typeRawValue: UInt, optionsRawValue: UInt) {
        guard let interruptionType = AVAudioSession.InterruptionType(rawValue: typeRawValue) else {
            return
        }

        switch interruptionType {
        case .began:
            wasInterruptedDuringRecording = isRecording
            guard isRecording else { return }

            recorder?.pause()
            stopTimers()
            isRecording = false
            isPaused = true
            statusText = "Paused by another audio source."
            publishRecordingLiveActivity(force: true)

        case .ended:
            defer { wasInterruptedDuringRecording = false }
            guard wasInterruptedDuringRecording, hasActiveSession else { return }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRawValue)

            guard options.contains(.shouldResume) else {
                statusText = "Paused."
                publishRecordingLiveActivity(force: true)
                return
            }

            do {
                try AVAudioSession.sharedInstance().setActive(true)
                recorder?.record()
                isRecording = true
                isPaused = false
                statusText = "Recording…"
                startTimers()
                publishRecordingLiveActivity(force: true)
            } catch {
                statusText = "Could not resume after interruption."
                publishRecordingLiveActivity(force: true)
            }

        @unknown default:
            break
        }
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

    private func resetWaveformLevels() {
        waveformLevels = Array(repeating: 0.1, count: 24)
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
