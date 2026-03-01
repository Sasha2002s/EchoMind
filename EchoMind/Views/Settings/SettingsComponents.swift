//
//  SettingsComponents.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsRow: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        // Why: rows are used as labels for links/buttons, so the full row must be tappable.
        .contentShape(Rectangle())
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .onChange(of: isOn) { _, _ in
            HapticsService.selectionChanged()
        }
    }
}

struct PickerRow<Content: View, Selection: Hashable>: View {
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
        .onChange(of: selection) { _, _ in
            HapticsService.selectionChanged()
        }
    }
}
