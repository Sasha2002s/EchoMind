//
//  StorageUsageView.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct StorageUsageView: View {
    @State private var snapshot: StorageUsageSnapshot = .empty
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Calculating storage usage...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Section("Overview") {
                    StorageCategoryGraph(entries: chartEntries)
                    LabeledContent("Total") {
                        Text(snapshot.totalBytes.byteSizeString)
                            .fontWeight(.semibold)
                    }
                }

                Section("Categories") {
                    usageRow(title: "Audio files", bytes: snapshot.audioBytes, color: .blue)
                    usageRow(title: "Transcripts + summaries", bytes: snapshot.textBytes, color: .orange)
                    usageRow(title: "Local models", bytes: snapshot.modelBytes, color: .green)
                }

                Section("Model Breakdown") {
                    if snapshot.modelItems.isEmpty {
                        Text("No local AI/transcription model files found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.modelItems) { item in
                            LabeledContent(item.name) {
                                Text(item.bytes.byteSizeString)
                            }
                        }
                    }
                }

                Section("About System Models") {
                    Text("Apple system Translation/Foundation Models are managed by iOS and are not measurable from app sandbox storage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Storage Usage")
        .task {
            await loadUsage()
        }
        .refreshable {
            await loadUsage()
        }
    }

    @MainActor
    private func loadUsage() async {
        isLoading = true
        // Why: folder scans can touch many files, so run off the main actor.
        // Create the service inside detached work to avoid MainActor capture warnings in Swift 6 mode.
        let loadedSnapshot = await Task.detached(priority: .userInitiated) {
            StorageUsageService().loadSnapshot()
        }.value
        snapshot = loadedSnapshot
        isLoading = false
    }

    @ViewBuilder
    private func usageRow(title: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(bytes.byteSizeString)
                .foregroundStyle(.secondary)
        }
    }

    private var chartEntries: [StorageChartEntry] {
        [
            StorageChartEntry(name: "Audio", bytes: snapshot.audioBytes, color: .blue),
            StorageChartEntry(name: "Text", bytes: snapshot.textBytes, color: .orange),
            StorageChartEntry(name: "Models", bytes: snapshot.modelBytes, color: .green)
        ]
    }
}

private struct StorageChartEntry: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let color: Color
}

private struct StorageCategoryGraph: View {
    let entries: [StorageChartEntry]

    private var maxBytes: Double {
        let maxValue = entries.map { Double($0.bytes) }.max() ?? 0
        return max(maxValue, 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.name)
                            .font(.subheadline)
                        Spacer()
                        Text(entry.bytes.byteSizeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 10)
                            Capsule(style: .continuous)
                                .fill(entry.color)
                                .frame(
                                    width: max(
                                        8,
                                        geometry.size.width * CGFloat(Double(entry.bytes) / maxBytes)
                                    ),
                                    height: 10
                                )
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension Int64 {
    var byteSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: self)
    }
}

#Preview {
    NavigationStack {
        StorageUsageView()
    }
}
