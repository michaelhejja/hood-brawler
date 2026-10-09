import SwiftUI

enum Game {
    static let title = "BRAWLER"   // working title
}

struct MenuView: View {
    let onLab: () -> Void

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
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                VStack(spacing: 16) {
                    Button("PLAY") {}
                        .buttonStyle(ChunkyButtonStyle(color: .orange))
                        .disabled(true)
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
            .font(.system(size: size, weight: .black, design: .rounded))
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
            .font(.system(.title3, design: .rounded, weight: .heavy))
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
