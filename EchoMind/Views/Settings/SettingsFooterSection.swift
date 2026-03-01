//
//  SettingsFooterSection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsFooterSection: View {
    var body: some View {
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

