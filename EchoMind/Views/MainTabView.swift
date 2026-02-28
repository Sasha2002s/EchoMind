import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            
                HomeView()
            
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView()
}
