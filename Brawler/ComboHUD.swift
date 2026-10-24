import SpriteKit

/// The "12 HITS" counter. It grows and heats up as the combo climbs, shows a rank word at milestones, and a thin bar
/// drains to show how long you have to land the next hit. A combo ends when the window runs out or the hero is hurt.
final class ComboHUD: SKNode {
    static let window: TimeInterval = 2.2
    private static let ranks: [(hits: Int, word: String)] = [(5, "NICE!"), (10, "GREAT!"), (15, "BRUTAL!"), (25, "SAVAGE!"), (40, "UNSTOPPABLE!")]

    private(set) var count = 0
    /// A finisher is armed: the swipe-up / swipe-down moves will be their powered-up versions.
    var finisherReady = false {
        didSet {
            guard finisherReady != oldValue else { return }
            readyLabel.removeAllActions()
            readyLabel.isHidden = !finisherReady
            if finisherReady { readyLabel.run(.repeatForever(.sequence([.scale(to: 1.14, duration: 0.25), .scale(to: 0.95, duration: 0.25)]))) }
        }
    }
    private(set) var best = 0
    private var expires: TimeInterval = 0
    private var lastHealth: CGFloat = -1
    private var rank = ""

    private let number = ComboHUD.label(size: 66)
    private let hits = ComboHUD.label(size: 28)
    private let rankLabel = ComboHUD.label(size: 28)
    private let readyLabel = ComboHUD.label(size: 26)
    func setReadyColor(_ c: SKColor) { readyLabel.fontColor = c }
    private let barBack = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 120, height: 7), cornerRadius: 3.5)
    private let bar = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 120, height: 7), cornerRadius: 3.5)

    override init() {
        super.init()
        number.horizontalAlignmentMode = .left; hits.horizontalAlignmentMode = .left; rankLabel.horizontalAlignmentMode = .left
        hits.text = "HITS"; ComboHUD.set(hits, "HITS")
        rankLabel.position = CGPoint(x: 0, y: -46)
        readyLabel.horizontalAlignmentMode = .left; ComboHUD.set(readyLabel, "FINISHER READY!")
        readyLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1); readyLabel.position = CGPoint(x: 0, y: -106); readyLabel.isHidden = true
        barBack.position = CGPoint(x: 0, y: -74); bar.position = barBack.position
        barBack.fillColor = SKColor(white: 0, alpha: 0.45); barBack.strokeColor = .clear
        bar.strokeColor = .clear; bar.zPosition = 1
        for n in [number, hits, rankLabel, readyLabel, barBack, bar] as [SKNode] { addChild(n) }
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func label(size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: GameFont.banner)
        l.fontSize = size; l.verticalAlignmentMode = .center
        let s = SKLabelNode(fontNamed: GameFont.banner)
        s.fontSize = size; s.fontColor = .black; s.verticalAlignmentMode = .center; s.horizontalAlignmentMode = l.horizontalAlignmentMode
        s.position = CGPoint(x: 3, y: -3); s.zPosition = -1
        l.addChild(s)
        return l
    }
    private static func set(_ l: SKLabelNode, _ text: String) {
        l.text = text
        if let s = l.children.first as? SKLabelNode { s.text = text; s.horizontalAlignmentMode = l.horizontalAlignmentMode }
    }

    private var tint: SKColor {
        switch count {
        case ..<5:  return .white
        case 5..<10: return SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        case 10..<20: return SKColor(red: 1, green: 0.6, blue: 0.15, alpha: 1)
        case 20..<35: return SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 1)
        default:    return SKColor(red: 1, green: 0.4, blue: 0.75, alpha: 1)
        }
    }

    /// Call once per frame with the number of hits the hero landed that frame.
    func update(now: TimeInterval, hits landed: Int, heroHealth: CGFloat, heroDead: Bool) {
        if lastHealth >= 0, heroHealth < lastHealth - 0.01 || heroDead { end("hurt") }
        lastHealth = heroHealth
        if landed > 0 {
            if count == 0 { removeAction(forKey: "fade"); alpha = 1; rank = "" }
            count += landed; best = max(best, count); expires = now + Self.window
            refresh()
        } else if count > 0, now >= expires {
            end("timeout")
        }
        if count > 0 { bar.xScale = max(0.001, CGFloat((expires - now) / Self.window)) }
    }

    private func refresh() {
        guard count >= 2 else { return }
        isHidden = false
        let g = 1 + min(0.6, CGFloat(count) * 0.015)
        ComboHUD.set(number, "\(count)")
        number.fontColor = tint; hits.fontColor = tint; bar.fillColor = tint
        number.removeAction(forKey: "pop")
        number.run(.sequence([.scale(to: g * 1.3, duration: 0.05), .scale(to: g, duration: 0.12)]), withKey: "pop")
        hits.position = CGPoint(x: number.frame.maxX + 8, y: -9)
        if let r = Self.ranks.last(where: { count >= $0.hits }), r.word != rank {
            rank = r.word
            ComboHUD.set(rankLabel, rank); rankLabel.fontColor = tint
            rankLabel.removeAction(forKey: "pop"); rankLabel.setScale(1)
            rankLabel.run(.sequence([.scale(to: 1.5, duration: 0.07), .scale(to: 1, duration: 0.2)]), withKey: "pop")
            NSLog("COMBO %d %@", count, rank)
        }
    }

    private func end(_ why: String) {
        guard count > 0 else { return }
        let shown = count >= 2
        if shown { NSLog("COMBO end %d (%@) best %d", count, why, best) }
        count = 0
        guard shown else { isHidden = true; return }
        if why == "hurt" { number.fontColor = SKColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1) }
        run(.sequence([.wait(forDuration: why == "hurt" ? 0.15 : 0.3), .fadeOut(withDuration: 0.3), .run { [weak self] in self?.isHidden = true }]), withKey: "fade")
    }
}
