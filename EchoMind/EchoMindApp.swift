//
//  EchoMindApp.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

@main
struct EchoMindApp: App {
    @UIApplicationDelegateAdaptor(BackgroundSessionAppDelegate.self) private var appDelegate
    @StateObject private var dependencies = AppDependencies.live()
    @AppStorage("settings.theme") private var theme: AppTheme = .system
    @AppStorage("settings.siriPermissionPromptRequested") private var siriPermissionPromptRequested: Bool = false
    @State private var didApplyStartupLiveActivityPolicy = false

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
                .preferredColorScheme(preferredColorScheme)
                .task {
                    guard !didApplyStartupLiveActivityPolicy else { return }
                    didApplyStartupLiveActivityPolicy = true
                    EchoMindLiveActivityManager.shared.applyStartupPolicyIfNeeded()
                    await requestSiriAuthorizationOnFirstLaunchIfNeeded()
                }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        // Why: apply the user's theme choice globally instead of showing a non-functional setting.
        switch theme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    @MainActor
    private func requestSiriAuthorizationOnFirstLaunchIfNeeded() async {
        guard !siriPermissionPromptRequested else { return }
        siriPermissionPromptRequested = true
        // Why: ask once on first launch so Siri/App Shortcuts can work without a hidden setup step.
        _ = await SiriAuthorizationService.requestAuthorizationIfNeeded()
    }
}
