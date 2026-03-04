//
//  ContentView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//

import SwiftUI

struct ContentView: View {
    let dependencies: AppDependencies

    var body: some View {
        MainTabView(dependencies: dependencies)
    }
}
#if DEBUG
#Preview {
    ContentView(dependencies: AppDependencies.preview())
}
#endif
