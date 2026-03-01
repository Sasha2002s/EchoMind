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

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
                .preferredColorScheme(preferredColorScheme)
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
}
