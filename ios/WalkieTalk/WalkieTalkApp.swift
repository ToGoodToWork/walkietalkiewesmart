import SwiftUI

@main
struct WalkieTalkApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { await auth.bootstrap() }
                .tint(.accentColor)
        }
    }
}
