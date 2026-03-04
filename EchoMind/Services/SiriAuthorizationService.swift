//
//  SiriAuthorizationService.swift
//  EchoMind
//
//  Created by Codex on 04.03.26.
//

import Foundation
import Intents

enum SiriAuthorizationService {
    enum Status: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
        case unknown
    }

    nonisolated static func currentStatus() -> Status {
        mapStatus(INPreferences.siriAuthorizationStatus())
    }

    nonisolated static func statusText(for status: Status) -> String {
        switch status {
        case .notDetermined:
            return "Not requested yet"
        case .authorized:
            return "Enabled"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unknown:
            return "Unknown"
        }
    }

    static func requestAuthorizationIfNeeded() async -> Status {
        let current = currentStatus()
        guard current == .notDetermined else { return current }
        return await requestAuthorization()
    }

    static func requestAuthorization() async -> Status {
        await withCheckedContinuation { continuation in
            INPreferences.requestSiriAuthorization { status in
                continuation.resume(returning: mapStatus(status))
            }
        }
    }

    nonisolated private static func mapStatus(_ status: INSiriAuthorizationStatus) -> Status {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}
