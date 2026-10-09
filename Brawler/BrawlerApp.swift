import SwiftUI

@main
struct BrawlerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum Screen { case menu, lab }

struct RootView: View {
    @State private var screen: Screen = .menu

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MenuView(onLab: { screen = .lab })
                    .transition(.opacity)
            case .lab:
                CharacterVisualizerView(onBack: { screen = .menu })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
