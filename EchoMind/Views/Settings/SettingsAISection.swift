//
//  SettingsAISection.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import SwiftUI

struct SettingsAISection: View {
    @Binding var defaultAIModel: DefaultAIModel
    @Binding var summaryStyle: SummaryStyle
    @Binding var taskDetectionEnabled: Bool

    var body: some View {
        Section("AI Output") {
            PickerRow(
                title: "Default AI Model",
                subtitle: defaultAIModel.displayName,
                systemImage: "cpu",
                selection: $defaultAIModel
            ) {
                ForEach(DefaultAIModel.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }

            PickerRow(
                title: "Summary Style",
                subtitle: summaryStyle.displayName,
                systemImage: "text.alignleft",
                selection: $summaryStyle
            ) {
                ForEach(SummaryStyle.allCases) { value in
                    Text(value.displayName).tag(value)
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
}
