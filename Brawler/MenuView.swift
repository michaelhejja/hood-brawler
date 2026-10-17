import SwiftUI

enum Game {
    static let title = "BRAWLER"   // working title
}

enum GameMode: Equatable { case campaign, survival, hub }
struct GameResult { let kills: Int; let won: Bool }

struct MenuView: View {
    let onPlay: () -> Void
    let onSurvival: () -> Void
    let onLab: () -> Void
    @State private var hero = HeroKind.selected

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.09, blue: 0.20), Color(red: 0.10, green: 0.30, blue: 0.33)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            HStack(spacing: 70) {
                VStack(alignment: .leading, spacing: 4) {
                    OutlinedText(text: Game.title, size: 84)
                    Text("working title")
                        .font(.custom(GameFont.ui, size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                }
                VStack(spacing: 16) {
                    Button("PLAY", action: onPlay)
                        .buttonStyle(ChunkyButtonStyle(color: .orange))
                    Button("SURVIVAL", action: onSurvival)
                        .buttonStyle(ChunkyButtonStyle(color: .red))
                    Button("HERO: \(hero.title)") {
                        hero = HeroKind(rawValue: (hero.rawValue + 1) % HeroKind.allCases.count) ?? .cloak
                        HeroKind.selected = hero
                    }
                    .buttonStyle(ChunkyButtonStyle(color: .blue))
                    Button("CHARACTER LAB", action: onLab)
                        .buttonStyle(ChunkyButtonStyle(color: .green))
                }
                .frame(width: 260)
            }
        }
    }
}

struct OutlinedText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.custom(GameFont.ui, size: size))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 3, y: 3)
            .shadow(color: .black, radius: 0, x: -3, y: -3)
            .shadow(color: .black, radius: 0, x: 3, y: -3)
            .shadow(color: .black, radius: 0, x: -3, y: 3)
    }
}

struct ChunkyButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom(GameFont.ui, size: 22))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(color))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 4))
            .shadow(color: .black, radius: 0, x: 0, y: configuration.isPressed ? 1 : 5)
            .offset(y: configuration.isPressed ? 4 : 0)
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct PauseView: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    var homeTitle = "HOME"
    let onHome: () -> Void
    var showBrightness = false
    @State private var brightness = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 0.5

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 22) {
                OutlinedText(text: "PAUSED", size: 72)
                VStack(spacing: 14) {
                    Button("RESUME", action: onResume)
                        .buttonStyle(ChunkyButtonStyle(color: .orange))
                    Button("RESTART", action: onRestart)
                        .buttonStyle(ChunkyButtonStyle(color: .gray))
                    Button(homeTitle, action: onHome)
                        .buttonStyle(ChunkyButtonStyle(color: .gray))
                }
                .frame(width: 260)
                .padding(.top, 8)
                if showBrightness {
                    VStack(spacing: 4) {
                        Text("BRIGHTNESS").font(.custom(GameFont.ui, size: 14)).foregroundStyle(.white)
                        Slider(value: Binding(get: { brightness }, set: { brightness = $0; UserDefaults.standard.set($0, forKey: "brightness") }), in: 0...1)
                    }
                    .frame(width: 260)
                }
            }
        }
    }
}

struct GameOverView: View {
    var title = "GAME OVER"
    var retryTitle = "TRY AGAIN"
    var homeTitle = "HOME"
    let kills: Int
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 22) {
                OutlinedText(text: title, size: 72)
                VStack(spacing: 2) {
                    Text("KILLS")
                        .font(.custom(GameFont.ui, size: 22))
                        .foregroundStyle(.white.opacity(0.7))
                    OutlinedText(text: "\(kills)", size: 96)
                }
                VStack(spacing: 14) {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(ChunkyButtonStyle(color: .orange))
                    Button(homeTitle, action: onHome)
                        .buttonStyle(ChunkyButtonStyle(color: .gray))
                }
                .frame(width: 260)
                .padding(.top, 8)
            }
        }
    }
}
