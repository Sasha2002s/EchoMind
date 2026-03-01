//
//  LibraryView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

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
