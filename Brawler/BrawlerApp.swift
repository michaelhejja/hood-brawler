import SwiftUI

@main
struct BrawlerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum Screen { case menu, lab, game }

struct RootView: View {
    @State private var screen: Screen = .menu

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MenuView(onPlay: { screen = .game }, onLab: { screen = .lab })
                    .transition(.opacity)
            case .game:
                GameView(onBack: { screen = .menu })
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
