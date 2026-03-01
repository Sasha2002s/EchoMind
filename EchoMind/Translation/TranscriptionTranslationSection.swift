//
//  TranscriptionTranslationSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct TranscriptionTranslationSection: View {
    let transcriptText: String
    @ObservedObject var viewModel: TranscriptionTranslationViewModel
    @State private var awaitingTranslationResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Picker("Translate to", selection: $viewModel.selectedLocale) {
                        ForEach(SpeechLocaleOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(viewModel.selectedLocale.shortTitle, systemImage: "globe")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .menuOrder(.fixed)

                Spacer()

                Button {
                    HapticsService.impact(.light)
                    awaitingTranslationResult = true
                    Task { await viewModel.translate(transcriptText: transcriptText) }
                } label: {
                    Label(viewModel.isTranslating ? "Translating..." : "Translate", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isTranslating || transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !viewModel.translatedTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Translated transcription")
                    .font(.subheadline.weight(.semibold))

                Text(viewModel.translatedTranscriptText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let translationError = viewModel.translationError {
                Text(translationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: transcriptText) { _, newValue in
            viewModel.handleTranscriptChange(newValue)
        }
        .onChange(of: viewModel.selectedLocale) { _, _ in
            HapticsService.selectionChanged()
        }
        .onChange(of: viewModel.translatedTranscriptText) { _, newValue in
            if awaitingTranslationResult && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HapticsService.notify(.success)
                awaitingTranslationResult = false
            }
        }
        .onChange(of: viewModel.translationError) { _, newValue in
            if awaitingTranslationResult && newValue != nil {
                HapticsService.notify(.error)
                awaitingTranslationResult = false
            }
        }
#if canImport(Translation)
        .translationTask(viewModel.translationConfiguration) { session in
            await viewModel.performFrameworkTranslation(using: session, transcriptText: transcriptText)
        }
#endif
    }
}
