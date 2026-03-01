//
//  RecordingDetail.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 28.02.26.
//

import SwiftUI

// MARK: - Detail

struct RecordingDetailView: View {
    let item: RecordingFile
    @ObservedObject var player: LibraryAudioPlayer

    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.shareStyle") private var shareStyle: ShareStylePreference = .audioOnly
    @StateObject private var vm: RecordingDetailViewModel
    @StateObject private var translationVM: SummaryTranslationViewModel
    @StateObject private var transcriptionTranslationVM: TranscriptionTranslationViewModel
    @State private var shareItems: [Any] = []
    @State private var isShareSheetPresented = false
    private let shareService = RecordingShareService()

    init(item: RecordingFile, player: LibraryAudioPlayer) {
        self.item = item
        self.player = player
        _vm = StateObject(wrappedValue: RecordingDetailViewModel(item: item, player: player))
        _translationVM = StateObject(wrappedValue: SummaryTranslationViewModel(audioURL: item.url))
        _transcriptionTranslationVM = StateObject(wrappedValue: TranscriptionTranslationViewModel(audioURL: item.url))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                playbackCard
                transcriptionCard
                deleteButton
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.onAppear()
        }
        .onDisappear {
            vm.onDisappear()
        }
        .onChange(of: vm.didDeleteRecording) { _, didDelete in
            if didDelete {
                HapticsService.notify(.success)
                dismiss()
            }
        }
        .onChange(of: vm.deleteError) { _, newError in
            if newError != nil {
                HapticsService.notify(.error)
            }
        }
        .onChange(of: vm.currentAudioURL) { _, newURL in
            translationVM.syncAudioURL(newURL)
            transcriptionTranslationVM.syncAudioURL(newURL)
        }
        .onChange(of: vm.selectedEngine) { _, _ in
            HapticsService.selectionChanged()
        }
        .onChange(of: vm.selectedSpeechLocale) { _, _ in
            HapticsService.selectionChanged()
        }
        .onChange(of: vm.selectedWhisperLocale) { _, _ in
            HapticsService.selectionChanged()
        }
        .sheet(isPresented: $isShareSheetPresented, onDismiss: {
            shareItems = []
        }) {
            ActivityView(items: shareItems)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.displayTitleForCurrentFile)
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                Text(item.createdAtFormatted)
                Text("•")
                Text(item.durationFormatted)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playback")
                    .font(.headline)

                Spacer()

                Button {
                    prepareShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Export audio")

                Button {
                    HapticsService.impact(.light)
                    player.toggle(url: vm.currentAudioURL, id: item.id)
                } label: {
                    Image(systemName: player.isPlaying(id: item.id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(player.isPlaying(id: item.id) ? "Pause" : "Play")
            }

            HStack {
                Text(player.isLoaded(id: item.id) ? player.currentTimeFormatted : "0:00")
                Spacer()
                Text(player.isLoaded(id: item.id) ? player.totalDurationFormatted : item.durationFormatted)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: {
                        player.isLoaded(id: item.id) ? player.currentTime : 0
                    },
                    set: { newValue in
                        if player.isLoaded(id: item.id) {
                            player.seek(to: newValue)
                        }
                    }
                ),
                in: 0...(max(player.isLoaded(id: item.id) ? player.totalDuration : item.duration, 0.01)),
                onEditingChanged: { isEditing in
                    if isEditing {
                        player.beginScrubbing()
                    } else {
                        player.endScrubbing()
                    }
                }
            )
            .disabled(!player.isLoaded(id: item.id))
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func prepareShare() {
        let items = shareService.makeShareItems(
            audioURL: vm.currentAudioURL,
            recordingTitle: vm.displayTitleForCurrentFile,
            style: shareStyle
        )
        guard !items.isEmpty else { return }
        shareItems = items
        isShareSheetPresented = true
        HapticsService.selectionChanged()
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                if vm.isLoadingTranscript || vm.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            Button {
                HapticsService.impact(.medium)
                Task {
                    await vm.transcribe()
                    if vm.transcriptionError == nil {
                        HapticsService.notify(.success)
                    } else {
                        HapticsService.notify(.error)
                    }
                }
            } label: {
                let hasTranscript = !vm.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Label(
                    vm.isTranscribing ? "Transcribing..." : (hasTranscript ? "Re-transcribe" : "Transcribe"),
                    systemImage: vm.selectedEngine.systemImage
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isTranscribing)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Engine")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Picker("Engine", selection: $vm.selectedEngine) {
                            ForEach(vm.availableEngines) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                    } label: {
                        Label(vm.selectedEngine.title, systemImage: vm.selectedEngine.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                    .menuOrder(.fixed)
                }

                if vm.selectedEngine == .appleSpeech {
                    HStack {
                        Text("Language")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Picker("Language", selection: $vm.selectedSpeechLocale) {
                                ForEach(SpeechLocaleOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(vm.selectedSpeechLocale.shortTitle, systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuOrder(.fixed)
                    }
                } else {
                    HStack {
                        Text("Language")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Picker("Language", selection: $vm.selectedWhisperLocale) {
                                ForEach(SpeechLocaleOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(vm.selectedWhisperLocale.shortTitle, systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuOrder(.fixed)
                    }
                }
            }

            let trimmedTranscript = vm.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedTranscript.isEmpty {
                Text("No transcription yet. You can add transcription later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                let transcriptWordCount = wordCount(for: trimmedTranscript)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isTranscriptHidden.toggle()
                    }
                    HapticsService.selectionChanged()
                } label: {
                    Label(vm.isTranscriptHidden ? "Show transcription" : "Hide transcription",
                          systemImage: vm.isTranscriptHidden ? "chevron.down" : "chevron.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Why: this plain button behaves like a row control and should be fully tappable.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("\(transcriptWordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !vm.isTranscriptHidden {
                    Text(vm.transcriptText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                TranscriptionTranslationSection(
                    transcriptText: vm.transcriptText,
                    viewModel: transcriptionTranslationVM
                )
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("Summary")
                        .font(.headline)

                    Spacer()

                    Button {
                        HapticsService.impact(.medium)
                        Task {
                            await vm.summarizeOnDevice()
                            if vm.summaryError == nil {
                                HapticsService.notify(.success)
                            } else {
                                HapticsService.notify(.error)
                            }
                        }
                    } label: {
                        let hasSummary = !vm.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Label(vm.isSummarizing ? "Summarizing..." : (hasSummary ? "Re-summarize" : "Summarize"), systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isSummarizing || trimmedTranscript.isEmpty)
                    .accessibilityHint("Creates a short on-device summary from the transcript")
                }

                if vm.isSummarizing {
                    ProgressView("Generating summary…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let trimmedSummary = vm.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmedSummary.isEmpty {
                    Text(trimmedTranscript.isEmpty ? "Transcribe first, then summarize." : "No summary yet. Tap Summarize to generate one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.isSummaryHidden.toggle()
                        }
                        HapticsService.selectionChanged()
                    } label: {
                        Label(vm.isSummaryHidden ? "Show summary" : "Hide summary",
                              systemImage: vm.isSummaryHidden ? "chevron.down" : "chevron.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Why: this plain button behaves like a row control and should be fully tappable.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if !vm.isSummaryHidden {
                        Text(vm.summaryText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        Divider().padding(.vertical, 2)
                        SummaryTranslationSection(summaryText: vm.summaryText, viewModel: translationVM)
                    }
                }
            }

            if let summaryError = vm.summaryError {
                Text(summaryError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let transcriptionError = vm.transcriptionError {
                Text(transcriptionError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let whisperStatus = vm.whisperStatus, vm.selectedEngine.isWhisper {
                Text(whisperStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func wordCount(for text: String) -> Int {
        // Why: word count should stay language-friendly and ignore punctuation-heavy tokens.
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            HapticsService.notify(.warning)
            vm.showDeleteConfirm = true
        } label: {
            Label("Delete recording", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $vm.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                HapticsService.notify(.warning)
                Task { await vm.deleteRecording() }
            }
            Button("Cancel", role: .cancel) {
                HapticsService.selectionChanged()
            }
        } message: {
            Text("This will permanently delete the audio and its transcription.")
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { vm.deleteError != nil }, set: { if !$0 { vm.deleteError = nil } })) {
            Button("OK", role: .cancel) { vm.deleteError = nil }
        } message: {
            Text(vm.deleteError ?? "Unknown error")
        }
    }
}

#Preview("Recording Detail") {
    NavigationStack {
        RecordingDetailView(
            item: LibraryView_PreviewsHelper.sampleRecordingFile(),
            player: LibraryAudioPlayer()
        )
    }
}
