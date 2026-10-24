import SpriteKit

/// Loads hand-drawn body parts. A part is a PNG named `<prefix>_<part>.png` in Brawler/Sprites, exported at the size of its cell
/// on the slicing template (Art/template_spec.json). Any part that is missing falls back to the skin's code-drawn shape,
/// so parts can be swapped in one at a time and mixed between characters.
enum SpriteParts {
    enum Part: String, CaseIterable { case head, torso, armWeapon = "arm_weapon", armOff = "arm_off", legBack = "leg_back", legFront = "leg_front", wingBack = "wing_back", wingFront = "wing_front" }

    /// Template pixels -> game points.
    static let pointsPerPixel: CGFloat = 0.128

    /// Cell size and pivot (from the cell's top-left, y down) in template pixels. Matches Art/template_spec.json.
    static let cells: [Part: (size: CGSize, pivot: CGPoint)] = [
        .head:      (CGSize(width: 708, height: 708), CGPoint(x: 354, y: 354)),
        .torso:     (CGSize(width: 412, height: 451), CGPoint(x: 206, y: 242)),
        .armWeapon: (CGSize(width: 224, height: 396), CGPoint(x: 140, y: 60)),
        .armOff:    (CGSize(width: 224, height: 396), CGPoint(x: 75, y: 58)),
        .legBack:   (CGSize(width: 256, height: 295), CGPoint(x: 128, y: 30)),
        .legFront:  (CGSize(width: 256, height: 295), CGPoint(x: 128, y: 30)),
        .wingBack:  (CGSize(width: 640, height: 760), CGPoint(x: 560, y: 150)),       // demon only: see Art/templates/demon_spec.json
        .wingFront: (CGSize(width: 640, height: 760), CGPoint(x: 560, y: 150)),
    ]

    private static var cache: [String: SKTexture?] = [:]
    private static var pivotCache: [String: [String: [CGFloat]]] = [:]

    /// Per-character pivot overrides, `<prefix>_pivots.json`: {"arm_weapon": [x, y], ...} in cell pixels from the top-left.
    private static func pivot(_ prefix: String, _ part: Part) -> CGPoint? {
        if pivotCache[prefix] == nil {
            var d: [String: [CGFloat]] = [:]
            if let url = Bundle.main.url(forResource: "\(prefix)_pivots", withExtension: "json"), let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]] { d = obj.mapValues { $0.map { CGFloat($0) } } }
            pivotCache[prefix] = d
        }
        guard let v = pivotCache[prefix]?[part.rawValue], v.count == 2 else { return nil }
        return CGPoint(x: v[0], y: v[1])
    }

    private static func texture(_ prefix: String, _ part: Part) -> SKTexture? {
        let name = "\(prefix)_\(part.rawValue)"
        if let hit = cache[name] { return hit }
        var tex: SKTexture?
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = UIImage(contentsOfFile: url.path) {
            tex = SKTexture(image: img); tex?.filteringMode = .linear
        }
        cache[name] = tex
        return tex
    }

    /// The drawn part, positioned so its pivot sits on the node's origin (the joint); nil if there is no art for it.
    static func node(_ prefix: String, _ part: Part) -> SKNode? {
        guard let tex = texture(prefix, part), let cell = cells[part] else { return nil }
        let px = tex.size()
        if abs(px.width - cell.size.width) > 2 || abs(px.height - cell.size.height) > 2 {
            NSLog("SPRITE %@_%@: %.0fx%.0f but the template cell is %.0fx%.0f (scaled to fit)", prefix, part.rawValue, px.width, px.height, cell.size.width, cell.size.height)
        }
        let s = SKSpriteNode(texture: tex)
        s.size = CGSize(width: cell.size.width * pointsPerPixel, height: cell.size.height * pointsPerPixel)
        let pv = pivot(prefix, part) ?? cell.pivot
        s.anchorPoint = CGPoint(x: pv.x / cell.size.width, y: 1 - pv.y / cell.size.height)
        return s
    }

    static func has(_ prefix: String) -> [Part] { Part.allCases.filter { texture(prefix, $0) != nil } }
}

/// Hand-drawn weapons: `weapon_<name>.png` (spaces become underscores) in Brawler/Sprites, sliced from Art/templates/weapon_spec.json by Art/slice_sheet.py.
/// A drawn weapon replaces the code art. The effects the code art animates (bow string, glows, bomb spark) are rebuilt here as overlays,
/// placed from the drawing's measured extents in weapon_meta.json. A weapon with no drawing keeps its code art, so they can be swapped in one at a time.
enum WeaponArt {
    private static var cache: [String: SKTexture?] = [:]

    /// name -> [grip x, grip y (cell pixels from the top-left), top, bottom, left, right (points from the grip, y up)]
    private static let meta: [String: [CGFloat]] = {
        guard let url = Bundle.main.url(forResource: "weapon_meta", withExtension: "json"), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]] else { return [:] }
        return obj.mapValues { $0.map { CGFloat($0) } }
    }()

    private static func texture(_ key: String) -> SKTexture? {
        if let hit = cache[key] { return hit }
        var tex: SKTexture?
        if let url = Bundle.main.url(forResource: "weapon_\(key)", withExtension: "png"), let img = UIImage(contentsOfFile: url.path) {
            tex = SKTexture(image: img); tex?.filteringMode = .linear
        }
        cache[key] = tex
        return tex
    }

    private static func pulse(_ n: SKNode, _ lo: CGFloat = 0.9, _ hi: CGFloat = 1.18, _ t: TimeInterval = 0.5) {
        n.run(.repeatForever(.sequence([.scale(to: hi, duration: t), .scale(to: lo, duration: t)])))
    }

    private static func blob(_ size: CGSize, _ c: SKColor, alpha: CGFloat, glow: CGFloat, at p: CGPoint, z: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(ellipseOf: size)
        n.fillColor = c.withAlphaComponent(alpha); n.strokeColor = .clear; n.glowWidth = glow
        n.position = p; n.zPosition = z
        return n
    }

    static func node(named name: String) -> SKNode? {
        let key = name.replacingOccurrences(of: " ", with: "_")
        guard let tex = texture(key), let m = meta[key], m.count == 6 else { return nil }
        let px = tex.size(), k = SpriteParts.pointsPerPixel
        let s = SKSpriteNode(texture: tex)
        s.size = CGSize(width: px.width * k, height: px.height * k)
        s.anchorPoint = CGPoint(x: m[0] / px.width, y: 1 - m[1] / px.height)      // the grip sits on the hand
        let top = m[2], bottom = m[3], left = m[4], right = m[5]
        let cx = (left + right) / 2, cy = (top + bottom) / 2, w = right - left, h = top - bottom
        switch key {
        case "bow":                                                        // the string isn't drawn: a straight one, and the pulled one with its arrow
            let line = CGMutablePath(); line.move(to: CGPoint(x: 0, y: bottom)); line.addLine(to: CGPoint(x: 0, y: top))
            let string = SKShapeNode(path: line); string.strokeColor = SKColor(white: 0.95, alpha: 1); string.lineWidth = 2
            s.addChild(string)
            let nocked = SKNode(); nocked.name = "nocked"; nocked.isHidden = true; nocked.zPosition = 1
            let pull = CGMutablePath(); pull.move(to: CGPoint(x: 0, y: bottom)); pull.addLine(to: CGPoint(x: -20, y: 0)); pull.addLine(to: CGPoint(x: 0, y: top))
            let pulled = SKShapeNode(path: pull); pulled.strokeColor = SKColor(white: 0.95, alpha: 1); pulled.lineWidth = 2
            nocked.addChild(pulled)
            nocked.addChild(Weapons.arrowArt(scale: 0.8, at: CGPoint(x: 4, y: 0)))
            s.addChild(nocked)
        case "staff", "ice_staff":                                         // a pulsing glow over the orb or crystal at the tip
            let c = key == "staff" ? SKColor(red: 0.6, green: 1, blue: 0.7, alpha: 1) : SKColor(red: 0.72, green: 0.95, blue: 1, alpha: 1)
            let g = blob(CGSize(width: 22, height: 22), c, alpha: 0.4, glow: 8, at: CGPoint(x: cx, y: top - 10), z: 1)
            pulse(g); s.addChild(g)
        case "shield":                                                     // the guard glow Fighter.setGuardCharge fades in
            let g = blob(CGSize(width: w + 14, height: h + 20), SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), alpha: 1, glow: 0, at: CGPoint(x: cx, y: cy), z: -1)
            g.name = "glow"; g.alpha = 0
            s.addChild(g)
        case "light_blade":                                                // the blade's glow
            s.addChild(blob(CGSize(width: w * 2 + 14, height: h + 10), SKColor(red: 1, green: 0.95, blue: 0.62, alpha: 1), alpha: 0.35, glow: 9, at: CGPoint(x: cx, y: cy), z: -1))
        case "bomb":                                                       // the fuse spark, which the fuse code blinks by name
            let spark = SKShapeNode(circleOfRadius: 4)
            spark.fillColor = SKColor(red: 1, green: 0.75, blue: 0.2, alpha: 1); spark.strokeColor = .clear; spark.glowWidth = 5
            spark.name = "light"; spark.position = CGPoint(x: cx, y: top); spark.zPosition = 1
            pulse(spark, 0.8, 1.5, 0.07); s.addChild(spark)
        default: break
        }
        return s
    }
}
