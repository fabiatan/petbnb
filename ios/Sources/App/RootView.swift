import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.status {
        case .bootstrapping:
            ProgressView("Loading…")
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabs()
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }
            PetListView()
                .tabItem {
                    Label("Pets", systemImage: "pawprint")
                }
        }
    }
}
