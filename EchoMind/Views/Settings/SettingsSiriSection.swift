//
//  SettingsSiriSection.swift
//  EchoMind
//
//  Created by Codex on 04.03.26.
//

import SwiftUI
import UIKit

struct SettingsSiriSection: View {
    @Environment(\.openURL) private var openURL
    @State private var siriStatus: SiriAuthorizationService.Status = SiriAuthorizationService.currentStatus()
    @State private var showCommands = false
    @State private var isRequestingAuthorization = false

    private let commandsByAction: [(title: String, commands: [String])] = [
        (
            title: "Start Recording",
            commands: [
                "Record with EchoMind",
                "Start recording with EchoMind",
                "Begin recording in EchoMind",
                "New recording in EchoMind",
                "Take voice note in EchoMind"
            ]
        ),
        (
            title: "Stop Recording",
            commands: [
                "Stop recording in EchoMind",
                "Finish recording in EchoMind",
                "End recording in EchoMind",
                "Save recording in EchoMind",
                "Done recording in EchoMind"
            ]
        ),
        (
            title: "Play Last Recording",
            commands: [
                "Play last recording in EchoMind",
                "Play latest recording in EchoMind",
                "Play newest recording in EchoMind",
                "Play my last recording in EchoMind"
            ]
        ),
        (
            title: "Transcribe Last Recording",
            commands: [
                "Transcribe last recording in EchoMind",
                "Transcribe latest recording in EchoMind",
                "Convert last recording to text in EchoMind",
                "Make transcript of last recording in EchoMind"
            ]
        ),
        (
            title: "Summarize Last Recording",
            commands: [
                "Summarize last recording in EchoMind",
                "Summarize latest recording in EchoMind",
                "Make summary of last recording in EchoMind",
                "Create summary in EchoMind"
            ]
        ),
        (
            title: "Rename Last Recording",
            commands: [
                "Name last recording in EchoMind",
                "Rename last recording in EchoMind",
                "Change last recording name in EchoMind",
                "Change name of last recording in EchoMind"
            ]
        ),
        (
            title: "Delete Last Recording",
            commands: [
                "Delete last recording in EchoMind",
                "Delete latest recording in EchoMind",
                "Remove last recording in EchoMind",
                "Erase last recording in EchoMind"
            ]
        )
    ]

    var body: some View {
        Section("Siri") {
            SettingsRow(
                title: "Siri & Shortcuts Status",
                subtitle: "\(SiriAuthorizationService.statusText(for: siriStatus)) • iOS Settings controls final Siri behavior",
                systemImage: "waveform.badge.mic"
            )

            if siriStatus == .notDetermined {
                Button {
                    Task { await requestSiriAuthorization() }
                } label: {
                    SettingsRow(
                        title: isRequestingAuthorization ? "Requesting…" : "Enable Siri for EchoMind",
                        subtitle: "Show iOS permission prompt",
                        systemImage: "checkmark.shield"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingAuthorization)
            }

            Button {
                HapticsService.selectionChanged()
                openAppSettings()
            } label: {
                SettingsRow(
                    title: "Open Siri Settings",
                    subtitle: "Manage Siri & Shortcuts permissions in iOS Settings",
                    systemImage: "gearshape"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                HapticsService.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommands.toggle()
                }
            } label: {
                SettingsRow(
                    title: showCommands ? "Hide Siri Commands" : "Show Siri Commands",
                    subtitle: "Examples you can say to Siri",
                    systemImage: showCommands ? "chevron.up.circle" : "chevron.down.circle"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCommands {
                ForEach(Array(commandsByAction.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))

                        ForEach(item.commands, id: \.self) { command in
                            Text("• \(command)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            siriStatus = SiriAuthorizationService.currentStatus()
        }
    }

    @MainActor
    private func requestSiriAuthorization() async {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        let status = await SiriAuthorizationService.requestAuthorizationIfNeeded()
        siriStatus = status
        if status == .authorized {
            HapticsService.notify(.success)
        } else {
            HapticsService.selectionChanged()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
