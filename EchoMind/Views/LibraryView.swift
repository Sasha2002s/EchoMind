//
//  LibraryView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI
import AVFoundation
import Combine


struct LibraryView: View {
    @State private var recordings: [RecordingFile] = []
    @State private var isLoading = false
    @StateObject private var player = LibraryAudioPlayer()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && recordings.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if recordings.isEmpty {
                    ContentUnavailableView(
                        "No recordings yet",
                        systemImage: "waveform",
                        description: Text("Create a recording from Home and it will appear here.")
                    )
                } else {
                    List {
                        ForEach(recordings) { item in
                            NavigationLink {
                                RecordingDetailView(item: item, player: player)
                            } label: {
                                RecordingRow(item: item)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Library")
            .onAppear { Task { await reload() } }
            .refreshable { await reload() }
            .onDisappear { player.stop() }
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        let loaded = await RecordingFileLoader.loadRecordingsFromDocuments()
        recordings = loaded
    }
}

// MARK: - Previews

#if DEBUG
enum LibraryView_PreviewsHelper {
    static func sampleRecordingFile() -> RecordingFile {
        // A stable URL for previews. It does not need to exist unless you press Play.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preview_recording.m4a")
        return RecordingFile(
            id: "preview_recording.m4a",
            url: url,
            createdAt: Date().addingTimeInterval(-3600),
            duration: 92
        )
    }
}
#endif

#Preview("Library") {
    LibraryView()
}

// MARK: - Row

private struct RecordingRow: View {
    let item: RecordingFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(item.createdAtFormatted)
                    Text("•")
                    Text(item.durationFormatted)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open recording")
    }
}

#Preview("Recording Row") {
    RecordingRow(item: LibraryView_PreviewsHelper.sampleRecordingFile())
        .padding()
}





// MARK: - Playback

@MainActor
final class LibraryAudioPlayer: ObservableObject {
    @Published private(set) var nowPlayingID: String? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var tick: AnyCancellable?

    func isPlaying(id: String) -> Bool {
        isPlaying && nowPlayingID == id
    }
    func isLoaded(id: String) -> Bool {
        nowPlayingID == id && player != nil
    }

    var currentTimeFormatted: String { formatTime(currentTime) }
    var totalDurationFormatted: String { formatTime(totalDuration) }

    func toggle(url: URL, id: String) {
        // If tapping the currently playing item, toggle pause/resume.
        if nowPlayingID == id, let p = player {
            if p.isPlaying {
                p.pause()
                isPlaying = false
                stopTicking()
            } else {
                p.play()
                isPlaying = true
                startTicking()
            }
            return
        }

        // Otherwise, start the new item.
        start(url: url, id: id)
    }

    func start(url: URL, id: String) {
        stop()

        do {
            try configureAudioSession()
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()

            player = p
            nowPlayingID = id
            isPlaying = true
            currentTime = p.currentTime
            totalDuration = p.duration
            startTicking()
        } catch {
            // If something fails, reset state.
            player = nil
            nowPlayingID = nil
            isPlaying = false
            stopTicking()
            currentTime = 0
            totalDuration = 0
            print("Playback error:", error)
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

        // Keep this максимально совместимо: `.playback` + `.default`.
        // Some option combos can throw OSStatus -50 on certain routes/devices.
        if #available(iOS 10.0, *) {
            try session.setCategory(.playback, mode: .default, options: [])
        } else {
            try session.setCategory(.playback, mode: .default)
        }

        try session.setActive(true)
    }
}

