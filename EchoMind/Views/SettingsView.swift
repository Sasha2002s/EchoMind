//
//  SettingsView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

struct SettingsView: View {
    // MARK: - User settings

    @AppStorage("settings.theme") private var theme: AppTheme = .system
    @AppStorage("settings.haptics") private var hapticsEnabled: Bool = true
    @AppStorage("settings.sounds") private var soundsEnabled: Bool = false

    @AppStorage("settings.transcriptionLanguage") private var transcriptionLanguage: TranscriptionLanguage = .auto
    @AppStorage("settings.summaryStyle") private var summaryStyle: SummaryStyle = .balanced
    @AppStorage("settings.taskDetection") private var taskDetectionEnabled: Bool = true

    @AppStorage("settings.keepAudio") private var keepAudio: KeepAudioPolicy = .always
    @AppStorage("settings.preventAutoLock") private var preventAutoLock: Bool = true

    @AppStorage("settings.whisperModel") private var whisperModel: WhisperModelChoice = .none

    @State private var showChangelog = false
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                recordingSection
                aiSection
                whisperSection
                storageSection
                supportSection

                changelogSection
                appFooter
            }
            .onAppear {
                vm.refreshWhisperModelInstalledState(for: whisperModel)
            }
            .onChange(of: whisperModel) { _, newValue in
                vm.refreshWhisperModelInstalledState(for: newValue)
            }
            .onDisappear {
                vm.cancelWhisperDownload()
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Sections

private extension SettingsView {
    var appearanceSection: some View {
        Section("Appearance") {
            PickerRow(
                title: "Theme",
                subtitle: theme.displayName,
                systemImage: "circle.lefthalf.filled",
                selection: $theme
            ) {
                ForEach(AppTheme.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }

            ToggleRow(
                title: "Haptics",
                subtitle: "Vibration feedback",
                systemImage: "hand.tap",
                isOn: $hapticsEnabled
            )

            ToggleRow(
                title: "Sounds",
                subtitle: "Start/stop sounds",
                systemImage: "speaker.wave.2",
                isOn: $soundsEnabled
            )
        }
    }

    var recordingSection: some View {
        Section("Recording") {
            ToggleRow(
                title: "Prevent Auto-Lock",
                subtitle: "Keep screen awake while recording",
                systemImage: "lock.open",
                isOn: $preventAutoLock
            )

            PickerRow(
                title: "Transcription Language",
                subtitle: transcriptionLanguage.displayName,
                systemImage: "globe",
                selection: $transcriptionLanguage
            ) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
        }
    }

    var aiSection: some View {
        Section("AI Output") {
            PickerRow(
                title: "Summary Style",
                subtitle: summaryStyle.displayName,
                systemImage: "text.alignleft",
                selection: $summaryStyle
            ) {
                ForEach(SummaryStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            ToggleRow(
                title: "Task Detection",
                subtitle: "Detect to-dos in your notes",
                systemImage: "checklist",
                isOn: $taskDetectionEnabled
            )
        }
    }

    var whisperSection: some View {
        Section("Local Whisper") {
            PickerRow(
                title: "Whisper Model",
                subtitle: whisperModel.displayName,
                systemImage: "arrow.down.circle",
                selection: $whisperModel
            ) {
                ForEach(WhisperModelChoice.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }

            if whisperModel == .none {
                SettingsRow(
                    title: "Offline transcription",
                    subtitle: "Select a model to enable on-device Whisper",
                    systemImage: "waveform.badge.mic"
                )
            } else {
                let ready = vm.whisperModelReady

                SettingsRow(
                    title: ready ? "Model ready" : "Model not downloaded",
                    subtitle: ready ? "Available offline" : "~450-600 MB download",
                    systemImage: ready ? "checkmark.seal" : "icloud.and.arrow.down"
                )

                if let whisperDownloadError = vm.whisperDownloadError {
                    Text(whisperDownloadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if vm.whisperIsDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        if let p = vm.whisperDownloadProgress {
                            ProgressView(value: p)
                            Text("Downloading... \(Int(p * 100))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                            Text("Preparing...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    if vm.whisperIsDownloading {
                        Button(role: .destructive) {
                            vm.cancelWhisperDownload()
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            vm.startWhisperDownload(for: whisperModel)
                        } label: {
                            Label("Download", systemImage: "arrow.down")
                        }
                        .disabled(vm.whisperModelReady || vm.whisperIsDownloading)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        vm.deleteWhisperModel(for: whisperModel)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled((!vm.whisperModelReady) || vm.whisperIsDownloading)
                }

                Text("Whisper runs fully on device. Download once, then you can transcribe without internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var storageSection: some View {
        Section("Storage") {
            PickerRow(
                title: "Keep Audio",
                subtitle: keepAudio.displayName,
                systemImage: "externaldrive",
                selection: $keepAudio
            ) {
                ForEach(KeepAudioPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            SettingsRow(
                title: "Storage Usage",
                subtitle: "Coming soon",
                systemImage: "chart.pie"
            )
        }
    }

    var supportSection: some View {
        Section("Support") {
            SettingsRow(
                title: "Send Feedback",
                subtitle: "Email us your thoughts",
                systemImage: "envelope"
            )

            SettingsRow(
                title: "Privacy Policy",
                subtitle: "Read before using",
                systemImage: "hand.raised"
            )

            SettingsRow(
                title: "Terms of Use",
                subtitle: "App rules and licensing",
                systemImage: "doc.text"
            )
        }
    }

    var changelogSection: some View {
        Section("Changelog") {
            Button {
                showChangelog = true
            } label: {
                SettingsRow(
                    title: "What’s New",
                    subtitle: "See recent changes",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView()
        }
    }

    var appFooter: some View {
        Section {
            VStack(spacing: 10) {
                AppLogoView()

                VStack(spacing: 2) {
                    Text(AppInfo.displayName)
                        .font(.headline)

                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Row components

private struct SettingsRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }
}

private struct PickerRow<Content: View, Selection: Hashable>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content

    var body: some View {
        Picker(selection: $selection) {
            content()
        } label: {
            SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }
}

// MARK: - Enums

private enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

private enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto
    case en
    case de
    case uk
    case ru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "English"
        case .de: return "German"
        case .uk: return "Ukrainian"
        case .ru: return "Russian"
        }
    }
}

private enum SummaryStyle: String, CaseIterable, Identifiable {
    case short
    case balanced
    case detailed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .balanced: return "Balanced"
        case .detailed: return "Detailed"
        }
    }
}

private enum KeepAudioPolicy: String, CaseIterable, Identifiable {
    case always
    case days7
    case days30
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .days7: return "7 days"
        case .days30: return "30 days"
        case .never: return "Never"
        }
    }
}

// MARK: - Changelog

private struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    Label("App project initialized", systemImage: "checkmark.seal")
                    Label("Recording + Library playback", systemImage: "waveform")
                }

                Section("Next") {
                    Label("Progress / Result screen", systemImage: "sparkles")
                    Label("Transcription + Summary", systemImage: "text.quote")
                }
            }
            .navigationTitle("Changelog")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Footer

private enum AppInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "EchoMind"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

private struct AppLogoView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 72, height: 72)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 40))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SettingsView()
}
