import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        ZStack {
            switch auth.phase {
            case .bootstrapping:
                ProgressView()
            case .loggedOut:
                AuthView()
                    .transition(.opacity)
            case .loggedIn(let me):
                HomeView(me: me)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.phase)
    }
}
