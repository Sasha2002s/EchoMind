import SwiftUI

struct MainTabView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            HomeView(recordingRepository: dependencies.recordingRepository)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            LibraryView(
                recordingRepository: dependencies.recordingRepository,
                voiceMemoImportService: dependencies.voiceMemoImportService,
                player: dependencies.libraryAudioPlayer
            )
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            SettingsView(viewModel: dependencies.settingsViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView(dependencies: AppDependencies.preview())
}
