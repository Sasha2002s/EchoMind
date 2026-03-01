//
//  LibraryView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let recordingRepository: any RecordingRepository
    let voiceMemoImportService: any VoiceMemoImporting
    @ObservedObject var player: LibraryAudioPlayer

    @State private var recordings: [RecordingFile] = []
    @State private var isLoading = false
    @State private var showFileImporter = false
    @State private var importMessage: ImportMessage?

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticsService.selectionChanged()
                        showFileImporter = true
                    } label: {
                        Image(systemName: "waveform.badge.plus")
                    }
                    .accessibilityLabel("Import Voice Memo")
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleImport(result: result) }
            }
            .alert(item: $importMessage) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.body),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear { Task { await reload() } }
            .refreshable { await reload() }
            .onDisappear { player.stop() }
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        // Why: use one repository for both Library and Home lists.
        let loaded = await recordingRepository.loadAllRecordings()
        recordings = loaded
    }

    @MainActor
    private func handleImport(result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else {
                importMessage = ImportMessage(
                    title: "Import failed",
                    body: "No file was selected."
                )
                return
            }

            do {
                let importedURL = try voiceMemoImportService.importAudioFile(from: sourceURL)
                await reload()
                HapticsService.notify(.success)
                importMessage = ImportMessage(
                    title: "Voice memo imported",
                    body: importedURL.lastPathComponent
                )
            } catch {
                HapticsService.notify(.error)
                importMessage = ImportMessage(
                    title: "Import failed",
                    body: error.localizedDescription
                )
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                return
            }
            HapticsService.notify(.error)
            importMessage = ImportMessage(
                title: "Import failed",
                body: error.localizedDescription
            )
        }
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
    LibraryView(
        recordingRepository: FileSystemRecordingRepository(),
        voiceMemoImportService: VoiceMemoImportService(),
        player: LibraryAudioPlayer()
    )
}

private struct ImportMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
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
