//
//  SettingsView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI
import ZIPFoundation

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
    @AppStorage("settings.whisperModelDownloaded") private var whisperModelDownloaded: Bool = false

    @State private var whisperIsDownloading: Bool = false
    @State private var whisperDownloadProgress: Double? = nil
    @State private var whisperDownloadError: String? = nil
    @State private var whisperModelInstalledOnDisk: Bool = false
    @State private var whisperDownloadTask: Task<Void, Never>? = nil

    @State private var showChangelog = false

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
                refreshWhisperModelInstalledState()
            }
            .onChange(of: whisperModel) { _, _ in
                refreshWhisperModelInstalledState()
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
                title: "Prevent Auto‑Lock",
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
                subtitle: "Detect to‑dos in your notes",
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
                    subtitle: "Select a model to enable on‑device Whisper",
                    systemImage: "waveform.badge.mic"
                )
            } else {
                let ready = whisperModelDownloaded || whisperModelInstalledOnDisk

                SettingsRow(
                    title: ready ? "Model ready" : "Model not downloaded",
                    subtitle: ready ? "Available offline" : "~450–600 MB download",
                    systemImage: ready ? "checkmark.seal" : "icloud.and.arrow.down"
                )

                if let whisperDownloadError {
                    Text(whisperDownloadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if whisperIsDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        if let p = whisperDownloadProgress {
                            ProgressView(value: p)
                            Text("Downloading… \(Int(p * 100))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                            Text("Preparing…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    if whisperIsDownloading {
                        Button(role: .destructive) {
                            whisperDownloadTask?.cancel()
                            whisperDownloadTask = nil
                            whisperIsDownloading = false
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            whisperDownloadTask?.cancel()
                            whisperDownloadTask = Task {
                                await downloadWhisperModelIfNeeded()
                            }
                        } label: {
                            Label("Download", systemImage: "arrow.down")
                        }
                        .disabled((whisperModelDownloaded || whisperModelInstalledOnDisk) || whisperIsDownloading)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        deleteWhisperModel()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled((!(whisperModelDownloaded || whisperModelInstalledOnDisk)) || whisperIsDownloading)
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

            // Placeholder row – we can wire real storage usage later.
            SettingsRow(
                title: "Storage Usage",
                subtitle: "Coming soon",
                systemImage: "chart.pie"
            )
        }
    }

    var supportSection: some View {
        Section("Support") {
            // These are placeholders – wire to real links later.
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
private enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case none
    case largeV3_547

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .largeV3_547: return "Large v3 (Compressed) ~550 MB"
        }
    }

    /// Folder name used by WhisperKit model repos (and by our on-device storage convention).
    var folderName: String {
        switch self {
        case .none: return ""
        case .largeV3_547: return "openai_whisper-large-v3-v20240930_547MB"
        }
    }
}

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

// MARK: - Whisper Model Download/Delete

extension SettingsView {
    private func modelRootFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("EchoMind", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func modelFolder() -> URL {
        modelRootFolder().appendingPathComponent(whisperModel.folderName, isDirectory: true)
    }

    private func modelZipURL() -> URL {
        // Your Cloudflare R2 public development URL
        let base = "https://pub-fd248852a2764fb0b71b284a4f678c9f.r2.dev"

        // Current implementation hosts a single file at the bucket root:
        //   https://.../whisper_model.zip
        // If you later host multiple models, switch to something like:
        //   /models/<folderName>.zip
        guard let url = URL(string: base + "/whisper_model.zip") else {
            preconditionFailure("Invalid R2 public URL")
        }
        return url
    }

    private struct ExpectedItemGroup {
        let alternatives: [String]
    }

    private func expectedModelItemGroups() -> [ExpectedItemGroup] {
        // Some zips contain compiled CoreML (.mlmodelc), others contain source models (.mlmodel).
        // We'll accept either for the three core model artifacts, plus the JSON configs.
        return [
            ExpectedItemGroup(alternatives: ["AudioEncoder.mlmodelc", "AudioEncoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["TextDecoder.mlmodelc", "TextDecoder.mlmodel"]),
            ExpectedItemGroup(alternatives: ["MelSpectrogram.mlmodelc", "MelSpectrogram.mlmodel"]),
            ExpectedItemGroup(alternatives: ["config.json"]),
            ExpectedItemGroup(alternatives: ["generation_config.json"])
        ]
    }

    private func isModelInstalled(at folder: URL) -> Bool {
        let fm = FileManager.default
        return expectedModelItemGroups().allSatisfy { group in
            group.alternatives.contains { name in
                fm.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
        }
    }

    private func refreshWhisperModelInstalledState() {
        guard whisperModel != .none else {
            whisperModelInstalledOnDisk = false
            whisperModelDownloaded = false
            whisperDownloadError = nil
            return
        }

        let folder = modelFolder()
        let installed = isModelInstalled(at: folder)
        whisperModelInstalledOnDisk = installed

        // Keep the persisted flag in sync with real disk state.
        if whisperModelDownloaded != installed {
            whisperModelDownloaded = installed
        }

        if installed {
            whisperDownloadError = nil
        }
    }

    private func findFolderContainingExpectedItems(startingAt root: URL, maxDepth: Int = 4) -> URL? {
        let fm = FileManager.default

        func isIgnorableFolderName(_ name: String) -> Bool {
            name.hasPrefix("__MACOSX") || name.hasPrefix(".")
        }

        func search(_ folder: URL, depth: Int) -> URL? {
            if isModelInstalled(at: folder) {
                return folder
            }
            guard depth < maxDepth else { return nil }

            let children = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children {
                guard let isDir = try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true else {
                    continue
                }
                if isIgnorableFolderName(child.lastPathComponent) { continue }
                if let found = search(child, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }

        return search(root, depth: 0)
    }

    private func normalizeUnzippedModelLayout(in destinationFolder: URL) throws {
        // If the zip contains a top-level folder (or __MACOSX), move the real model contents
        // to `destinationFolder` so the app always reads from a stable path.
        let fm = FileManager.default

        // If already correct, nothing to do.
        if isModelInstalled(at: destinationFolder) {
            return
        }

        guard let installRoot = findFolderContainingExpectedItems(startingAt: destinationFolder) else {
            return
        }

        // If the expected items are not directly in destinationFolder, move them up.
        if installRoot != destinationFolder {
            let items = (try fm.contentsOfDirectory(at: installRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
            for item in items {
                let dest = destinationFolder.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) {
                    try? fm.removeItem(at: dest)
                }
                try fm.moveItem(at: item, to: dest)
            }

            // Clean up the now-empty installRoot folder if possible.
            try? fm.removeItem(at: installRoot)
        }

        // Remove __MACOSX if it exists.
        let macosx = destinationFolder.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosx.path) {
            try? fm.removeItem(at: macosx)
        }
    }

    private func downloadWhisperModelIfNeeded() async {
        guard whisperModel != .none else { return }
        refreshWhisperModelInstalledState()
        guard !(whisperModelDownloaded || whisperModelInstalledOnDisk) else { return }
        guard !whisperIsDownloading else { return }

        whisperDownloadError = nil
        whisperDownloadProgress = nil
        whisperIsDownloading = true
        defer {
            whisperIsDownloading = false
            whisperDownloadProgress = nil
        }

        let fm = FileManager.default
        let folder = modelFolder()
        let zipDest = modelRootFolder().appendingPathComponent("whisper_model.zip")

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)

            // Download with progress (stream bytes -> file)
            let request = URLRequest(url: modelZipURL(), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }

            let expectedLength = response.expectedContentLength
            var received: Int64 = 0

            // Replace existing zip if any
            if fm.fileExists(atPath: zipDest.path) {
                try fm.removeItem(at: zipDest)
            }
            fm.createFile(atPath: zipDest.path, contents: nil)

            let handle = try FileHandle(forWritingTo: zipDest)
            defer { try? handle.close() }

            // URLSession.AsyncBytes yields UInt8, so buffer into Data chunks for efficient file writes.
            var buffer: [UInt8] = []
            buffer.reserveCapacity(64 * 1024)

            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)

                if buffer.count >= 64 * 1024 {
                    let data = Data(buffer)
                    try handle.write(contentsOf: data)
                    received += Int64(data.count)
                    buffer.removeAll(keepingCapacity: true)

                    if expectedLength > 0 {
                        let p = min(1.0, max(0.0, Double(received) / Double(expectedLength)))
                        await MainActor.run {
                            whisperDownloadProgress = p
                        }
                    } else {
                        await MainActor.run {
                            whisperDownloadProgress = nil
                        }
                    }
                }
            }

            // Flush remaining bytes
            if !buffer.isEmpty {
                let data = Data(buffer)
                try handle.write(contentsOf: data)
                received += Int64(data.count)
                buffer.removeAll(keepingCapacity: false)

                if expectedLength > 0 {
                    let p = min(1.0, max(0.0, Double(received) / Double(expectedLength)))
                    await MainActor.run {
                        whisperDownloadProgress = p
                    }
                }
            }

            // Ensure we end at 100% if we know the size
            if expectedLength > 0 {
                await MainActor.run {
                    whisperDownloadProgress = 1.0
                }
            }

            // Clean any previous partial install
            if fm.fileExists(atPath: folder.path) {
                // Remove folder contents (keep folder itself)
                let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                for item in items {
                    try? fm.removeItem(at: item)
                }
            }

            // Unzip into the model folder
            try fm.unzipItem(at: zipDest, to: folder)

            // Normalize common zip layouts (top-level folder, __MACOSX, extra nesting, etc.).
            try normalizeUnzippedModelLayout(in: folder)

            // Validate install
            guard isModelInstalled(at: folder) else {
                throw NSError(
                    domain: "EchoMind.ModelInstall",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unzipped, but expected model files were not found. This usually means the zip layout is different than expected (e.g. contains a top-level folder, __MACOSX, or the model files aren’t at the root). Ensure the zip includes AudioEncoder/TextDecoder/MelSpectrogram (.mlmodelc or .mlmodel) plus config.json and generation_config.json."]
                )
            }

            whisperModelDownloaded = true
            whisperModelInstalledOnDisk = true
            whisperDownloadError = nil
        } catch is CancellationError {
            // User tapped Stop (or task was cancelled). Keep state clean and do not show an error.
            whisperDownloadError = nil
            whisperDownloadProgress = nil
            whisperModelDownloaded = false
            whisperModelInstalledOnDisk = false
        } catch {
            whisperModelDownloaded = false
            whisperModelInstalledOnDisk = false
            whisperDownloadProgress = nil
            whisperDownloadError = "Download/install failed: \(error.localizedDescription)"
        }
        whisperDownloadTask = nil
    }

    private func deleteWhisperModel() {
        whisperDownloadError = nil

        let folder = modelFolder()
        let zip = modelRootFolder().appendingPathComponent("whisper_model.zip")

        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: zip)

        whisperModelDownloaded = false
        whisperModelInstalledOnDisk = false
        refreshWhisperModelInstalledState()
    }
}
