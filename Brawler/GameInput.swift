import UIKit

enum SwipeDirection { case up, down, left, right }
enum Gesture: Equatable {
    case tap
    case swipe(SwipeDirection)
}

/// All input tuning in one place. Start generous, tighten after playtesting.
enum InputTuning {
    static let swipeDistance: CGFloat = 25          // pt before a right-side drag counts as a swipe
    static let tapMaxDistance: CGFloat = 12
    static let tapMaxDuration: TimeInterval = 0.3
    static let deadZone: CGFloat = 8                // left-side drag ignored below this
    static let fullDrag: CGFloat = 80               // left-side drag distance for full intensity
    static let keyboardWalk: CGFloat = 0.4
    static let keyboardRun: CGFloat = 1.0
}

struct DebugTouch {
    let isLeft: Bool
    let origin: CGPoint     // view coordinates
    let current: CGPoint
}

/// Screen is split 50/50 by where a touch STARTS. Left = movement, right = actions.
/// Emits abstract inputs (movement vector + gestures) so touch, keyboard and scripted backends are interchangeable.
final class InputController {
    var onGesture: ((Gesture) -> Void)?

    private struct Track {
        let isLeft: Bool
        var origin: CGPoint
        var current: CGPoint
        let startTime: TimeInterval
        var lastTime: TimeInterval
        var fired = false
    }

    private var tracks: [ObjectIdentifier: Track] = [:]
    private var touchDragSpeed: CGFloat = 0
    private var keys = Set<Character>()
    private var keyRun = false

    // MARK: Movement output (direction is +y up, unit length)

    private var leftTrack: Track? { tracks.values.first { $0.isLeft } }

    private func vector(for t: Track) -> (dir: CGVector, intensity: CGFloat) {
        let dx = t.current.x - t.origin.x, dy = t.origin.y - t.current.y
        let dist = hypot(dx, dy)
        guard dist > InputTuning.deadZone else { return (.zero, 0) }
        let i = min(1, (dist - InputTuning.deadZone) / (InputTuning.fullDrag - InputTuning.deadZone))
        return (CGVector(dx: dx / dist, dy: dy / dist), i)
    }

    private var keyDirection: CGVector {
        let dx = (keys.contains("d") ? 1 : 0) - (keys.contains("a") ? 1 : 0)
        let dy = (keys.contains("w") ? 1 : 0) - (keys.contains("s") ? 1 : 0)
        let len = hypot(CGFloat(dx), CGFloat(dy))
        return len == 0 ? .zero : CGVector(dx: CGFloat(dx) / len, dy: CGFloat(dy) / len)
    }

    var direction: CGVector { leftTrack.map { vector(for: $0).dir } ?? keyDirection }

    /// 0...1. How hard the thumb is pushing (distance from the floating origin).
    var intensity: CGFloat {
        if let t = leftTrack { return vector(for: t).intensity }
        let d = keyDirection
        guard d.dx != 0 || d.dy != 0 else { return 0 }
        return keyRun ? InputTuning.keyboardRun : InputTuning.keyboardWalk
    }

    /// Smoothed thumb speed in pt/s. Faster drags accelerate the hero faster.
    var dragSpeed: CGFloat { leftTrack == nil ? 0 : touchDragSpeed }

    var debugTouches: [DebugTouch] {
        tracks.values.map { DebugTouch(isLeft: $0.isLeft, origin: $0.origin, current: $0.current) }
    }

    func update(dt: TimeInterval) {
        touchDragSpeed *= CGFloat(exp(-8 * dt))   // touchesMoved doesn't fire when the thumb rests
    }

    // MARK: Touch backend

    func began(_ touches: Set<UITouch>, in view: UIView) {
        for t in touches {
            let p = t.location(in: view)
            tracks[ObjectIdentifier(t)] = Track(isLeft: p.x < view.bounds.midX, origin: p, current: p,
                                                startTime: t.timestamp, lastTime: t.timestamp)
        }
    }

    func moved(_ touches: Set<UITouch>, in view: UIView) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard var tr = tracks[id] else { continue }
            let p = t.location(in: view)
            let dt = max(t.timestamp - tr.lastTime, 0.001)

            if tr.isLeft {
                let inst = hypot(p.x - tr.current.x, p.y - tr.current.y) / CGFloat(dt)
                touchDragSpeed = touchDragSpeed * 0.7 + min(inst, 3000) * 0.3
                // Floating origin trails the thumb so you never run out of screen
                let dx = p.x - tr.origin.x, dy = p.y - tr.origin.y
                let dist = hypot(dx, dy), limit = InputTuning.fullDrag * 1.25
                if dist > limit {
                    tr.origin.x += dx / dist * (dist - limit)
                    tr.origin.y += dy / dist * (dist - limit)
                }
            } else if !tr.fired {
                let dx = p.x - tr.origin.x, dy = p.y - tr.origin.y
                if hypot(dx, dy) >= InputTuning.swipeDistance {
                    tr.fired = true          // fires immediately, not on release
                    let dir: SwipeDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy < 0 ? .up : .down)
                    onGesture?(.swipe(dir))
                }
            }
            tr.current = p
            tr.lastTime = t.timestamp
            tracks[id] = tr
        }
    }

    func ended(_ touches: Set<UITouch>, in view: UIView) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let tr = tracks.removeValue(forKey: id) else { continue }
            if !tr.isLeft, !tr.fired {
                let p = t.location(in: view)
                if hypot(p.x - tr.origin.x, p.y - tr.origin.y) <= InputTuning.tapMaxDistance,
                   t.timestamp - tr.startTime <= InputTuning.tapMaxDuration {
                    onGesture?(.tap)
                }
            }
        }
        if leftTrack == nil { touchDragSpeed = 0 }
    }

    func cancelled(_ touches: Set<UITouch>) {
        touches.forEach { tracks.removeValue(forKey: ObjectIdentifier($0)) }
        if leftTrack == nil { touchDragSpeed = 0 }
    }

    // MARK: Keyboard backend (simulator): WASD = move (Shift = run), arrows = swipes, Space = tap

    func keyDown(_ c: Character, run: Bool) { keys.insert(c); keyRun = run }
    func keyUp(_ c: Character) { keys.remove(c) }
    func fire(_ g: Gesture) { onGesture?(g) }
}
