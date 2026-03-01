//
//  HomeView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

struct HomeView: View {
    let recordingRepository: any RecordingRepository
    let player: LibraryAudioPlayer

    @State private var showingRecording = false
    @State private var recent: [RecordingFile] = []
    @State private var lastSavedURL: URL?
    @State private var showSavedBanner = false
    @StateObject private var autoTranscriptionService = AutoTranscriptionService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    recordCard

                    recentSection

                    Spacer(minLength: 10)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .task {
                await autoTranscriptionService.processQueuedTranscriptionsInForeground()
                await reloadRecent()
            }
            .sheet(isPresented: $showingRecording) {
                RecordingView { url in
                    lastSavedURL = url
                    Task { await reloadRecent() }
                    Task {
                        await autoTranscriptionService.transcribeIfNeeded(audioURL: url)
                        await reloadRecent()
                    }
                    showSavedBanner = true
                }
            }
            .overlay(alignment: .top) {
                if showSavedBanner {
                    SavedBannerView(title: "Saved", subtitle: lastSavedURL?.lastPathComponent)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                withAnimation { showSavedBanner = false }
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    HomeView(
        recordingRepository: FileSystemRecordingRepository(),
        player: LibraryAudioPlayer()
    )
}

// MARK: - UI

private extension HomeView {
    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EchoMind")
                .font(.largeTitle.weight(.semibold))
            Text("Record a thought. Get a clean note.")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Tap the mic to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var recordCard: some View {
        VStack(spacing: 14) {
            Button {
                HapticsService.impact(.medium)
                showingRecording = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 116, height: 116)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 44, weight: .semibold))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start recording")

            VStack(spacing: 4) {
                Text("Tap to record")
                    .font(.headline)

                Text("Speak naturally — we’ll handle the rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                QuickActionChip(title: "Ideas", systemImage: "lightbulb")
                QuickActionChip(title: "Study", systemImage: "graduationcap")
                QuickActionChip(title: "Tasks", systemImage: "checklist")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent recordings")
                .font(.headline)

            if recent.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "waveform",
                    description: Text("Your newest recordings will show up here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(recent) { item in
                        NavigationLink {
                            RecordingDetailView(item: item, player: player)
                        } label: {
                            RecentRecordingRow(item: item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    @MainActor
    func reloadRecent() async {
        // Why: keep filesystem concerns in a repository so the view stays UI-only.
        recent = await recordingRepository.loadRecentRecordings(limit: 3)
    }
}

// MARK: - Components

private struct QuickActionChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

private struct RecentRecordingRow: View {
    let item: RecordingFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .contentShape(Rectangle())
    }
}

private struct SavedBannerView: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}
