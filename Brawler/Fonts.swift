import SwiftUI
import SpriteKit
import CoreText

/// The game's typefaces, by role. Change a font for a whole theme here and nothing else.
enum GameFont {
    static let banner = "Bangers-Regular"      // in-game: boss titles, banners, "!" alerts, the kill counter
    static let speech = "PatrickHand-Regular"  // in-game: speech bubbles and floating text (BLOCK, SCORCHED, damage)
    static let ui     = "LilitaOne"    // SwiftUI: menus, buttons, pause and game-over screens

    static let bundled = ["Bangers-Regular", "ComicNeue-Bold", "LilitaOne", "PatrickHand-Regular"]

    /// Registers every .ttf in the app bundle. Call once at launch.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        for name in [banner, speech, ui] where UIFont(name: name, size: 12) == nil {
            NSLog("FONT missing: %@ (falls back to the system font)", name)
        }
        NSLog("FONT registered %d files; banner=%d speech=%d ui=%d", urls.count, UIFont(name: banner, size: 12) != nil ? 1 : 0, UIFont(name: speech, size: 12) != nil ? 1 : 0, UIFont(name: ui, size: 12) != nil ? 1 : 0)
    }
}

/// White text with a thick black outline, as the game's comic lettering.
struct OutlinedLabel: View {
    let text: String
    let font: String
    let size: CGFloat
    var color: Color = .white
    var outline: CGFloat = 2

    var body: some View {
        Text(text)
            .font(.custom(font, size: size))
            .foregroundStyle(color)
            .lineLimit(1).fixedSize()
            .shadow(color: .black, radius: 0, x: outline, y: outline)
            .shadow(color: .black, radius: 0, x: -outline, y: -outline)
            .shadow(color: .black, radius: 0, x: outline, y: -outline)
            .shadow(color: .black, radius: 0, x: -outline, y: outline)
    }
}

/// `-fonts`: our real strings in each candidate typeface, on a night-time backdrop.
struct FontPreviewView: View {
    let onBack: () -> Void
    private let banners = ["Bangers-Regular", "LilitaOne", "Menlo-Bold"]
    private let speeches = ["ComicNeue-Bold", "LilitaOne", "PatrickHand-Regular", "Menlo-Bold"]

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.10, blue: 0.17).ignoresSafeArea()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("BANNER").font(.caption.bold()).foregroundStyle(.gray)
                    ForEach(banners, id: \.self) { f in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(f).font(.system(size: 10)).foregroundStyle(.gray)
                            OutlinedLabel(text: "THE DOPPELGÄNGER", font: f, size: 34, outline: 3)
                            OutlinedLabel(text: "THE LANTERN WRAITH", font: f, size: 34, color: Color(red: 1, green: 0.85, blue: 0.3), outline: 3)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("SPEECH / ALERT / UI").font(.caption.bold()).foregroundStyle(.gray)
                    ForEach(speeches, id: \.self) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f).font(.system(size: 10)).foregroundStyle(.gray)
                            HStack(spacing: 10) {
                                OutlinedLabel(text: "I SEE YOU", font: f, size: 19)
                                OutlinedLabel(text: "Hello, me.", font: f, size: 18)
                                OutlinedLabel(text: "BLOCK", font: f, size: 19, color: Color(red: 1, green: 0.85, blue: 0.4))
                                OutlinedLabel(text: "SCORCHED", font: f, size: 19, color: Color(red: 1, green: 0.55, blue: 0.15))
                            }
                            HStack(spacing: 14) {
                                Text("RESUME").font(.custom(f, size: 20)).foregroundStyle(.white)
                                    .padding(.horizontal, 22).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
                                OutlinedLabel(text: "Come get it! Score 1,240", font: f, size: 16, outline: 1.5)
                            }
                        }
                    }
                }
            }
            .padding(24)
            VStack { HStack { Spacer(); Button("BACK", action: onBack).buttonStyle(.borderedProminent) }; Spacer() }.padding()
        }
    }
}
