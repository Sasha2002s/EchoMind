//
//  EchoMindLiveActivityLiveActivity.swift
//  EchoMindLiveActivity
//
//  Created by Codex on 03.03.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct EchoMindRecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case recording
            case paused
        }

        var status: Status
        var elapsedSeconds: Int
    }

    var sessionID: String
}

struct EchoMindModelDownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case preparing
            case downloading
            case paused
            case installing
            case finished
            case failed
        }

        var status: Status
        var progress: Double?
        var detailText: String?
    }

    var modelName: String
}

struct EchoMindRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EchoMindRecordingActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("EchoMind", systemImage: context.state.symbolName)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(echoMindDurationString(context.state.elapsedSeconds))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                Text(context.state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(echoMindDurationString(context.state.elapsedSeconds))
                        .font(.headline)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(echoMindCompactDurationString(context.state.elapsedSeconds))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }
}

struct EchoMindModelDownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EchoMindModelDownloadActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: context.state.symbolName)
                    Text(context.attributes.modelName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let progress = context.state.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                if context.state.status == .downloading, let progress = context.state.progress {
                    ProgressView(value: progress)
                } else if context.state.status == .preparing || context.state.status == .installing {
                    ProgressView()
                }

                Text(context.state.detailLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let progress = context.state.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.headline)
                            .monospacedDigit()
                    } else {
                        Text(context.state.compactTrailingLabel)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detailLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.compactTrailingLabel)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

private extension EchoMindRecordingActivityAttributes.ContentState {
    var symbolName: String {
        switch status {
        case .recording:
            return "mic.fill"
        case .paused:
            return "pause.fill"
        }
    }

    var statusText: String {
        switch status {
        case .recording:
            return "Recording in progress"
        case .paused:
            return "Recording paused"
        }
    }
}

private extension EchoMindModelDownloadActivityAttributes.ContentState {
    var symbolName: String {
        switch status {
        case .preparing:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .installing:
            return "shippingbox.fill"
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var detailLabel: String {
        if let detailText, !detailText.isEmpty {
            return detailText
        }

        switch status {
        case .preparing:
            return "Preparing download..."
        case .downloading:
            return "Downloading model..."
        case .paused:
            return "Paused in Low Power Mode"
        case .installing:
            return "Installing model..."
        case .finished:
            return "Model ready"
        case .failed:
            return "Download failed"
        }
    }

    var compactTrailingLabel: String {
        switch status {
        case .preparing:
            return "..."
        case .downloading:
            if let progress {
                return "\(Int(progress * 100))%"
            }
            return "..."
        case .paused:
            return "||"
        case .installing:
            return "..."
        case .finished:
            return "OK"
        case .failed:
            return "ERR"
        }
    }
}

private func echoMindDurationString(_ totalSeconds: Int) -> String {
    let clamped = max(0, totalSeconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let seconds = clamped % 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

private func echoMindCompactDurationString(_ totalSeconds: Int) -> String {
    let clamped = max(0, totalSeconds)
    let minutes = (clamped % 3600) / 60
    let seconds = clamped % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

