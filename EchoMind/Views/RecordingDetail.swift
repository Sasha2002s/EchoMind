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
    @StateObject private var vm: RecordingDetailViewModel
    @StateObject private var translationVM: SummaryTranslationViewModel

    init(item: RecordingFile, player: LibraryAudioPlayer) {
        self.item = item
        self.player = player
        _vm = StateObject(wrappedValue: RecordingDetailViewModel(item: item, player: player))
        _translationVM = StateObject(wrappedValue: SummaryTranslationViewModel(audioURL: item.url))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                playbackCard
                transcriptionCard
                summarizeButton
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
                dismiss()
            }
        }
        .onChange(of: vm.currentAudioURL) { _, newURL in
            translationVM.syncAudioURL(newURL)
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

                ShareLink(item: vm.currentAudioURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Export audio")

                Button {
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
                in: 0...(max(player.isLoaded(id: item.id) ? player.totalDuration : item.duration, 0.01))
            )
            .disabled(!player.isLoaded(id: item.id))
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcription")
                    .font(.headline)

                Spacer()

                if vm.isLoadingTranscript || vm.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Engine")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Picker("Engine", selection: $vm.selectedEngine) {
                            ForEach(TranscriptionEngine.allCases) { engine in
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
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isTranscriptHidden.toggle()
                    }
                } label: {
                    Label(vm.isTranscriptHidden ? "Show transcription" : "Hide transcription",
                          systemImage: vm.isTranscriptHidden ? "chevron.down" : "chevron.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !vm.isTranscriptHidden {
                    Text(vm.transcriptText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            let trimmedSummary = vm.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedSummary.isEmpty {
                Divider().padding(.vertical, 4)

                Text("Summary")
                    .font(.headline)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isSummaryHidden.toggle()
                    }
                } label: {
                    Label(vm.isSummaryHidden ? "Show summary" : "Hide summary",
                          systemImage: vm.isSummaryHidden ? "chevron.down" : "chevron.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !vm.isSummaryHidden {
                    Text(vm.summaryText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    Divider().padding(.vertical, 4)
                    SummaryTranslationSection(summaryText: vm.summaryText, viewModel: translationVM)
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

            if let whisperStatus = vm.whisperStatus, vm.selectedEngine == .whisper {
                Text(whisperStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await vm.transcribe() }
            } label: {
                let hasTranscript = !vm.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Label(
                    vm.isTranscribing ? "Transcribing..." : (hasTranscript ? "Re-transcribe" : "Transcribe"),
                    systemImage: vm.selectedEngine.systemImage
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isTranscribing)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summarizeButton: some View {
        Button {
            Task { await vm.summarizeOnDevice() }
        } label: {
            let hasSummary = !vm.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Label(vm.isSummarizing ? "Summarizing..." : (hasSummary ? "Re-summarize" : "Summarize"), systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.isSummarizing)
        .accessibilityHint("Creates a short on-device summary from the transcript")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
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
                Task { await vm.deleteRecording() }
            }
            Button("Cancel", role: .cancel) {}
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
