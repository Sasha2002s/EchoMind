//
//  SiriLaunchRequestStore.swift
//  EchoMind
//
//  Created by Codex on 04.03.26.
//

import Foundation

enum SiriLaunchRequestStore {
    private static let startRecordingRequestKey = "siri.request.startRecording"
    private static let stopRecordingRequestKey = "siri.request.stopRecording"
    private static let playLastRecordingRequestKey = "siri.request.playLastRecording"

    nonisolated static func queueStartRecording() {
        UserDefaults.standard.set(true, forKey: startRecordingRequestKey)
    }

    nonisolated static func consumeStartRecordingRequest() -> Bool {
        let defaults = UserDefaults.standard
        let shouldStartRecording = defaults.bool(forKey: startRecordingRequestKey)
        if shouldStartRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: startRecordingRequestKey)
        }
        return shouldStartRecording
    }

    nonisolated static func queueStopRecording() {
        UserDefaults.standard.set(true, forKey: stopRecordingRequestKey)
    }

    nonisolated static func consumeStopRecordingRequest() -> Bool {
        let defaults = UserDefaults.standard
        let shouldStopRecording = defaults.bool(forKey: stopRecordingRequestKey)
        if shouldStopRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: stopRecordingRequestKey)
        }
        return shouldStopRecording
    }

    nonisolated static func queuePlayLastRecording() {
        UserDefaults.standard.set(true, forKey: playLastRecordingRequestKey)
    }

    nonisolated static func consumePlayLastRecordingRequest() -> Bool {
        let defaults = UserDefaults.standard
        let shouldPlayLastRecording = defaults.bool(forKey: playLastRecordingRequestKey)
        if shouldPlayLastRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: playLastRecordingRequestKey)
        }
        return shouldPlayLastRecording
    }
}
