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
    private let fileService = RecordingDetailFileService()
    private let exportService = RecordingExportService()
    private let shareService = RecordingShareService()
    @AppStorage("settings.defaultExportFormat") private var defaultExportFormat: ExportFormatPreference = .m4a
    @AppStorage("settings.shareStyle") private var shareStyle: ShareStylePreference = .audioOnly

    @State private var recordings: [RecordingFile] = []
    @State private var isLoading = false
    @State private var showFileImporter = false
    @State private var userMessage: UserMessage?
    @State private var pendingDeleteItem: RecordingFile?
    @State private var pendingRenameItem: RecordingFile?
    @State private var renameInput: String = ""
    @State private var exportDocument: ExportDocument?
    @State private var exportDefaultName: String = "Recording"
    @State private var isExporting = false
    @State private var shareItems: [Any] = []
    @State private var isShareSheetPresented = false

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
                            .contextMenu {
                                Button {
                                    prepareShare(for: item)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }

                                Button {
                                    Task { await prepareExport(for: item) }
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.down")
                                }

                                Button {
                                    renameInput = item.displayTitle
                                    pendingRenameItem = item
                                    HapticsService.selectionChanged()
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    pendingDeleteItem = item
                                    HapticsService.notify(.warning)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportDocument?.contentType ?? .audio,
                defaultFilename: exportDefaultName
            ) { result in
                switch result {
                case .success:
                    HapticsService.notify(.success)
                    userMessage = UserMessage(
                        title: "Exported",
                        body: "Recording exported successfully."
                    )
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                        return
                    }
                    HapticsService.notify(.error)
                    userMessage = UserMessage(
                        title: "Export failed",
                        body: error.localizedDescription
                    )
                }
                exportDocument = nil
            }
            .sheet(isPresented: $isShareSheetPresented, onDismiss: {
                shareItems = []
            }) {
                ActivityView(items: shareItems)
            }
            .confirmationDialog(
                "Delete this recording?",
                isPresented: Binding(
                    get: { pendingDeleteItem != nil },
                    set: { if !$0 { pendingDeleteItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteItem
            ) { item in
                Button("Delete", role: .destructive) {
                    Task {
                        await handleDelete(item: item)
                        pendingDeleteItem = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    HapticsService.selectionChanged()
                    pendingDeleteItem = nil
                }
            } message: { _ in
                Text("This will permanently delete audio and related text files.")
            }
            .alert(
                "Rename recording",
                isPresented: Binding(
                    get: { pendingRenameItem != nil },
                    set: { if !$0 { pendingRenameItem = nil } }
                ),
                presenting: pendingRenameItem
            ) { item in
                TextField("New name", text: $renameInput)
                Button("Save") {
                    Task {
                        await handleRename(item: item, newName: renameInput)
                        pendingRenameItem = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    HapticsService.selectionChanged()
                    pendingRenameItem = nil
                }
            } message: { _ in
                Text("Enter a new title for this recording.")
            }
            .alert(item: $userMessage) { message in
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
                userMessage = UserMessage(
                    title: "Import failed",
                    body: "No file was selected."
                )
                return
            }

            do {
                let importedURL = try voiceMemoImportService.importAudioFile(from: sourceURL)
                await reload()
                HapticsService.notify(.success)
                userMessage = UserMessage(
                    title: "Voice memo imported",
                    body: importedURL.lastPathComponent
                )
            } catch {
                HapticsService.notify(.error)
                userMessage = UserMessage(
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
            userMessage = UserMessage(
                title: "Import failed",
                body: error.localizedDescription
            )
        }
    }

    @MainActor
    private func prepareExport(for item: RecordingFile) async {
        do {
            // Why: export should hand out a stable data snapshot from app sandbox to Files/share targets.
            let payload = try await exportService.prepareExport(
                audioURL: item.url,
                defaultName: item.fileName,
                format: defaultExportFormat
            )
            exportDocument = ExportDocument(data: payload.data, contentType: payload.contentType)
            exportDefaultName = payload.defaultFilename
            isExporting = true
            HapticsService.selectionChanged()
        } catch {
            HapticsService.notify(.error)
            userMessage = UserMessage(
                title: "Export failed",
                body: error.localizedDescription
            )
        }
    }

    @MainActor
    private func prepareShare(for item: RecordingFile) {
        let items = shareService.makeShareItems(
            audioURL: item.url,
            recordingTitle: item.displayTitle,
            style: shareStyle
        )
        guard !items.isEmpty else { return }
        shareItems = items
        isShareSheetPresented = true
        HapticsService.selectionChanged()
    }

    @MainActor
    private func handleDelete(item: RecordingFile) async {
        do {
            if player.isPlaying(id: item.id) {
                player.stop()
            }
            try fileService.deleteRecordingBundle(audioURL: item.url, locales: SpeechLocaleOption.allCases)
            await reload()
            HapticsService.notify(.success)
        } catch {
            HapticsService.notify(.error)
            userMessage = UserMessage(
                title: "Delete failed",
                body: error.localizedDescription
            )
        }
    }

    @MainActor
    private func handleRename(item: RecordingFile, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            HapticsService.notify(.warning)
            userMessage = UserMessage(
                title: "Rename failed",
                body: "Please enter a non-empty name."
            )
            return
        }

        do {
            if player.isPlaying(id: item.id) {
                player.stop()
            }

            let renamedURL = try fileService.renameRecordingAndSidecars(
                audioURL: item.url,
                newName: trimmed,
                locales: SpeechLocaleOption.allCases
            )

            if renamedURL == item.url {
                HapticsService.notify(.warning)
                userMessage = UserMessage(
                    title: "Rename not applied",
                    body: "The name is unchanged or already exists."
                )
                return
            }

            await reload()
            HapticsService.notify(.success)
        } catch {
            HapticsService.notify(.error)
            userMessage = UserMessage(
                title: "Rename failed",
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

private struct UserMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            .audio,
            .plainText,
            .wav,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "md") ?? .plainText
        ]
    }

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(audioURL: URL) throws {
        data = try Data(contentsOf: audioURL)
        contentType = UTType(filenameExtension: audioURL.pathExtension) ?? .audio
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
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
#if DEBUG
#Preview("Recording Row") {
    RecordingRow(item: LibraryView_PreviewsHelper.sampleRecordingFile())
        .padding()
}
#endif
