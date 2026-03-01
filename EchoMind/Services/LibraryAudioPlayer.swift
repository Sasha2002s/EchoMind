//
//  LibraryAudioPlayer.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import Foundation
import AVFoundation
import Combine
import os

@MainActor
final class LibraryAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var nowPlayingID: String? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var tick: AnyCancellable?
    private var shouldResumeAfterScrub = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EchoMind",
        category: "LibraryAudioPlayer"
    )

    override init() {
        super.init()
    }

    func isPlaying(id: String) -> Bool {
        isPlaying && nowPlayingID == id
    }

    func isLoaded(id: String) -> Bool {
        nowPlayingID == id && player != nil
    }

    var currentTimeFormatted: String { formatTime(currentTime) }
    var totalDurationFormatted: String { formatTime(totalDuration) }

    func toggle(url: URL, id: String) {
        if nowPlayingID == id, let p = player {
            if p.isPlaying {
                p.pause()
                isPlaying = false
                stopTicking()
            } else {
                // Why: replay from the start when user taps play on a finished item.
                if p.duration > 0, p.currentTime >= p.duration - 0.05 {
                    p.currentTime = 0
                    currentTime = 0
                }
                p.play()
                isPlaying = true
                startTicking()
            }
            return
        }

        start(url: url, id: id)
    }

    func start(url: URL, id: String) {
        stop()

        do {
            try configureAudioSession()
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.delegate = self
            p.prepareToPlay()
            p.play()

            player = p
            nowPlayingID = id
            isPlaying = true
            currentTime = p.currentTime
            totalDuration = p.duration
            startTicking()
        } catch {
            player = nil
            nowPlayingID = nil
            isPlaying = false
            stopTicking()
            currentTime = 0
            totalDuration = 0
            // Why: use structured logging instead of print for production diagnostics.
            logger.error("Playback error: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        nowPlayingID = nil
        isPlaying = false
        stopTicking()
        currentTime = 0
        totalDuration = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seek(to seconds: TimeInterval) {
        guard let p = player else { return }
        let clamped = max(0, min(seconds, totalDuration))
        p.currentTime = clamped
        currentTime = clamped
    }

    func beginScrubbing() {
        guard let p = player else { return }
        shouldResumeAfterScrub = p.isPlaying

        // Why: pausing while dragging avoids loud seek artifacts during live playback.
        if p.isPlaying {
            p.pause()
            isPlaying = false
            stopTicking()
        }
    }

    func endScrubbing() {
        guard let p = player else { return }
        defer { shouldResumeAfterScrub = false }

        guard shouldResumeAfterScrub else { return }
        p.play()
        isPlaying = true
        startTicking()
    }

    private func startTicking() {
        tick?.cancel()
        tick = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                self.totalDuration = p.duration
            }
    }

    private func stopTicking() {
        tick?.cancel()
        tick = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Keep category setup conservative for broad device/route compatibility.
        if #available(iOS 10.0, *) {
            try session.setCategory(.playback, mode: .default, options: [])
        } else {
            try session.setCategory(.playback, mode: .default)
        }

        try session.setActive(true)
    }
}

extension LibraryAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            // Why: explicit completion handling keeps UI state in sync at track end.
            self.isPlaying = false
            self.stopTicking()
            self.currentTime = player.duration
            self.totalDuration = player.duration
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.stop()
        }
    }
}
