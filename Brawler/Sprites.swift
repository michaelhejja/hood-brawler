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
