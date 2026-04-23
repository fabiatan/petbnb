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
            PetListView()
        }
    }
}
