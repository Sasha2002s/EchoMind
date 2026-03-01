//
//  SummaryTranslationSection.swift
//  EchoMind
//
//  Created by Codex on 28.02.26.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct SummaryTranslationSection: View {
    let summaryText: String
    @ObservedObject var viewModel: SummaryTranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Translate summary")
                    .font(.headline)

                Spacer()

                Menu {
                    Picker("Translate to", selection: $viewModel.selectedLocale) {
                        ForEach(SpeechLocaleOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(viewModel.selectedLocale.shortTitle, systemImage: "globe")
                        .labelStyle(.titleAndIcon)
                }
                .menuOrder(.fixed)
            }

            Button {
                Task { await viewModel.translate(summaryText: summaryText) }
            } label: {
                Label(viewModel.isTranslating ? "Translating..." : "Translate", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isTranslating || summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !viewModel.translatedSummaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Translation")
                    .font(.headline)

                Text(viewModel.translatedSummaryText)
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
        .onChange(of: summaryText) { _, newValue in
            viewModel.handleSummaryChange(newValue)
        }
#if canImport(Translation)
        .translationTask(viewModel.translationConfiguration) { session in
            await viewModel.performFrameworkTranslation(using: session, summaryText: summaryText)
        }
#endif
    }
}
