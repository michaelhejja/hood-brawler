import SwiftUI

@main
struct BrawlerApp: App {
    init() { GameFont.register() }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum Screen: Equatable { case menu, lab, fonts, game(GameMode) }

struct RootView: View {
    @State private var screen: Screen = ProcessInfo.processInfo.arguments.contains("-hub") ? .game(.hub) : ProcessInfo.processInfo.arguments.contains("-survival") ? .game(.survival) : (ProcessInfo.processInfo.arguments.contains("-game") ? .game(.campaign) : (ProcessInfo.processInfo.arguments.contains("-lab") ? .lab : (ProcessInfo.processInfo.arguments.contains("-fonts") ? .fonts : .menu)))

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MenuView(onPlay: { screen = .game(.hub) }, onSurvival: { screen = .game(.survival) })
                    .transition(.opacity)
            case .game(let mode):
                GameView(mode: mode, onBack: { screen = .menu })
                    .transition(.opacity)
            case .lab:
                CharacterVisualizerView(onBack: { screen = .menu })
                    .transition(.opacity)
            case .fonts:
                FontPreviewView(onBack: { screen = .menu })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
