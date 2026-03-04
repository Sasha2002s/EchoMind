//
//  EchoMindLiveActivityManager.swift
//  EchoMind
//
//  Created by Codex on 03.03.26.
//

import Foundation
import ActivityKit

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

@MainActor
final class EchoMindLiveActivityManager {
    static let liveActivitiesEnabledSettingKey = "settings.liveActivitiesEnabled"

    static let shared = EchoMindLiveActivityManager()
    private static let liveActivitiesPromptedKey = "settings.liveActivitiesPermissionPrompted"

    private let defaults: UserDefaults
    private var recordingActivityID: String?
    private var modelDownloadActivityID: String?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func applyStartupPolicyIfNeeded() {
        guard #available(iOS 16.2, *) else { return }

        if !liveActivitiesEnabled {
            endAllActivitiesNow()
            return
        }

        requestPermissionPromptIfNeeded()
    }

    func setLiveActivitiesEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.liveActivitiesEnabledSettingKey)

        guard #available(iOS 16.2, *) else { return }
        if isEnabled {
            requestPermissionPromptIfNeeded()
        } else {
            endAllActivitiesNow()
        }
    }

    func upsertRecording(isPaused: Bool, elapsedSeconds: Int) {
        guard #available(iOS 16.2, *) else { return }
        guard liveActivitiesEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = EchoMindRecordingActivityAttributes.ContentState(
            status: isPaused ? .paused : .recording,
            elapsedSeconds: max(0, elapsedSeconds)
        )

        Task { @MainActor in
            if let activity = currentRecordingActivity() {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                return
            }

            do {
                let attributes = EchoMindRecordingActivityAttributes(sessionID: UUID().uuidString)
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                recordingActivityID = activity.id
            } catch {
                recordingActivityID = nil
            }
        }
    }

    func endRecording(elapsedSeconds: Int) {
        guard #available(iOS 16.2, *) else { return }

        let finalState = EchoMindRecordingActivityAttributes.ContentState(
            status: .paused,
            elapsedSeconds: max(0, elapsedSeconds)
        )

        Task { @MainActor in
            guard let activity = currentRecordingActivity() else { return }
            await activity.end(
                ActivityContent(state: finalState, staleDate: Date()),
                dismissalPolicy: .immediate
            )
            recordingActivityID = nil
        }
    }

    func upsertModelDownload(
        modelName: String,
        status: EchoMindModelDownloadActivityAttributes.ContentState.Status,
        progress: Double?,
        detailText: String?
    ) {
        guard #available(iOS 16.2, *) else { return }
        guard liveActivitiesEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let normalizedProgress: Double?
        if let progress {
            normalizedProgress = min(1, max(0, progress))
        } else {
            normalizedProgress = nil
        }

        let state = EchoMindModelDownloadActivityAttributes.ContentState(
            status: status,
            progress: normalizedProgress,
            detailText: detailText
        )

        Task { @MainActor in
            if let activity = currentModelDownloadActivity(), activity.attributes.modelName != modelName {
                await activity.end(
                    ActivityContent(state: state, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
                modelDownloadActivityID = nil
            }

            if let activity = currentModelDownloadActivity() {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                return
            }

            do {
                let attributes = EchoMindModelDownloadActivityAttributes(modelName: modelName)
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                modelDownloadActivityID = activity.id
            } catch {
                modelDownloadActivityID = nil
            }
        }
    }

    func finishModelDownload(
        modelName: String,
        success: Bool,
        detailText: String?
    ) {
        guard #available(iOS 16.2, *) else { return }
        guard liveActivitiesEnabled else { return }

        let finalState = EchoMindModelDownloadActivityAttributes.ContentState(
            status: success ? .finished : .failed,
            progress: success ? 1 : nil,
            detailText: detailText
        )

        Task { @MainActor in
            if let activity = currentModelDownloadActivity() {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .default
                )
                modelDownloadActivityID = nil
                return
            }

            // Why: if app relaunched and we missed the active handle, still surface terminal state briefly.
            do {
                let attributes = EchoMindModelDownloadActivityAttributes(modelName: modelName)
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: finalState, staleDate: nil),
                    pushType: nil
                )
                await activity.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .default
                )
            } catch {
                modelDownloadActivityID = nil
            }
        }
    }

    func cancelModelDownloadIfNeeded(modelName: String) {
        guard #available(iOS 16.2, *) else { return }

        let finalState = EchoMindModelDownloadActivityAttributes.ContentState(
            status: .failed,
            progress: nil,
            detailText: "Download cancelled."
        )

        Task { @MainActor in
            guard let activity = currentModelDownloadActivity() else { return }
            if activity.attributes.modelName == modelName || modelName == "Whisper model" {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
                modelDownloadActivityID = nil
            }
        }
    }

    private func currentRecordingActivity() -> Activity<EchoMindRecordingActivityAttributes>? {
        if let recordingActivityID,
           let activity = Activity<EchoMindRecordingActivityAttributes>.activities.first(where: { $0.id == recordingActivityID }) {
            return activity
        }

        let first = Activity<EchoMindRecordingActivityAttributes>.activities.first
        recordingActivityID = first?.id
        return first
    }

    private func currentModelDownloadActivity() -> Activity<EchoMindModelDownloadActivityAttributes>? {
        if let modelDownloadActivityID,
           let activity = Activity<EchoMindModelDownloadActivityAttributes>.activities.first(where: { $0.id == modelDownloadActivityID }) {
            return activity
        }

        let first = Activity<EchoMindModelDownloadActivityAttributes>.activities.first
        modelDownloadActivityID = first?.id
        return first
    }

    private var liveActivitiesEnabled: Bool {
        defaults.object(forKey: Self.liveActivitiesEnabledSettingKey) as? Bool ?? true
    }

    private func requestPermissionPromptIfNeeded() {
        guard #available(iOS 16.2, *) else { return }
        guard liveActivitiesEnabled else { return }
        guard defaults.bool(forKey: Self.liveActivitiesPromptedKey) == false else { return }

        defaults.set(true, forKey: Self.liveActivitiesPromptedKey)

        let initialState = EchoMindRecordingActivityAttributes.ContentState(
            status: .paused,
            elapsedSeconds: 0
        )

        Task { @MainActor in
            do {
                let attributes = EchoMindRecordingActivityAttributes(sessionID: "permission-\(UUID().uuidString)")
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: initialState, staleDate: nil),
                    pushType: nil
                )
                await activity.end(
                    ActivityContent(state: initialState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            } catch {
                // Why: no-op if system declines prompt or live activities are unavailable.
            }
        }
    }

    private func endAllActivitiesNow() {
        guard #available(iOS 16.2, *) else { return }

        let recordingState = EchoMindRecordingActivityAttributes.ContentState(
            status: .paused,
            elapsedSeconds: 0
        )
        let downloadState = EchoMindModelDownloadActivityAttributes.ContentState(
            status: .failed,
            progress: nil,
            detailText: "Live Activities disabled."
        )

        Task { @MainActor in
            for activity in Activity<EchoMindRecordingActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: recordingState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
            for activity in Activity<EchoMindModelDownloadActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: downloadState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
            recordingActivityID = nil
            modelDownloadActivityID = nil
        }
    }
}
