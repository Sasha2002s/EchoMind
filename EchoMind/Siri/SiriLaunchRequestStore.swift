//
//  SiriLaunchRequestStore.swift
//  EchoMind
//
//  Created by Codex on 04.03.26.
//

import Foundation

enum SiriLaunchRequestStore {
    nonisolated static func queueStartRecording() {
        // Why: local literals avoid main-actor static-property isolation warnings under Swift 6 mode.
        let key = "siri.request.startRecording"
        UserDefaults.standard.set(true, forKey: key)
    }

    nonisolated static func consumeStartRecordingRequest() -> Bool {
        let key = "siri.request.startRecording"
        let defaults = UserDefaults.standard
        let shouldStartRecording = defaults.bool(forKey: key)
        if shouldStartRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: key)
        }
        return shouldStartRecording
    }

    nonisolated static func queueStopRecording() {
        let key = "siri.request.stopRecording"
        UserDefaults.standard.set(true, forKey: key)
    }

    nonisolated static func consumeStopRecordingRequest() -> Bool {
        let key = "siri.request.stopRecording"
        let defaults = UserDefaults.standard
        let shouldStopRecording = defaults.bool(forKey: key)
        if shouldStopRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: key)
        }
        return shouldStopRecording
    }

    nonisolated static func queuePlayLastRecording() {
        let key = "siri.request.playLastRecording"
        UserDefaults.standard.set(true, forKey: key)
    }

    nonisolated static func consumePlayLastRecordingRequest() -> Bool {
        let key = "siri.request.playLastRecording"
        let defaults = UserDefaults.standard
        let shouldPlayLastRecording = defaults.bool(forKey: key)
        if shouldPlayLastRecording {
            // Why: consume-once prevents stale Siri requests from replaying on later app launches.
            defaults.set(false, forKey: key)
        }
        return shouldPlayLastRecording
    }
}
