//
//  BackgroundSessionAppDelegate.swift
//  EchoMind
//
//  Created by Codex on 01.03.26.
//

import UIKit

final class BackgroundSessionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Why: BGTaskScheduler handlers must be registered at launch.
        BackgroundTranscriptionManager.registerBackgroundTask()
        BackgroundTranscriptionManager.scheduleBackgroundProcessing()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Why: keep queued transcription jobs eligible for system-run processing windows.
        BackgroundTranscriptionManager.scheduleBackgroundProcessing()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Why: reconnect background URLSession callbacks after app relaunch.
        WhisperBackgroundDownloadManager.shared.handleBackgroundEvents(
            for: identifier,
            completionHandler: completionHandler
        )
    }
}
