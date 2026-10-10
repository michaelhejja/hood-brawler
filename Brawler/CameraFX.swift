import CoreGraphics
import Foundation

/// How dramatic a moment is. The bigger the moment, the bigger the effect.
/// Zoom values are the fraction the camera closes in (0.08 = 8% closer). `slow` is the game's time scale at the peak.
struct Emphasis {
    var windup: CGFloat = 0        // gentle zoom as the move starts (anticipation, plays even if the move misses)
    var impact: CGFloat = 0        // zoom when the move connects
    var slow: CGFloat = 1          // time scale at the peak (1 = none)
    var hold: TimeInterval = 0     // seconds the peak is held
    var release: TimeInterval = 0.35

    static let none    = Emphasis()
    static let light   = Emphasis(impact: 0.02, hold: 0.04, release: 0.25)
    static let medium  = Emphasis(windup: 0.01, impact: 0.045, slow: 0.8, hold: 0.08, release: 0.3)
    static let heavy   = Emphasis(windup: 0.03, impact: 0.08, slow: 0.55, hold: 0.2, release: 0.4)
    static let massive = Emphasis(windup: 0.04, impact: 0.13, slow: 0.35, hold: 0.32, release: 0.55)
    static let kill    = Emphasis(impact: 0.05, slow: 0.6, hold: 0.15, release: 0.35)    // any KO, whatever landed it
}

/// Overlapping zoom / slow-mo beats on real time. Zoom takes the biggest active beat, time scale the slowest.
final class CameraFX {
    private struct Beat {
        let start: TimeInterval
        let attack: TimeInterval, hold: TimeInterval, release: TimeInterval
        let zoom: CGFloat, slow: CGFloat
        var end: TimeInterval { start + attack + hold + release }

        func envelope(_ t: TimeInterval) -> CGFloat {
            let u = t - start
            func smooth(_ x: Double) -> CGFloat { let c = min(1, max(0, x)); return CGFloat(c * c * (3 - 2 * c)) }
            if u <= 0 { return 0 }
            if u < attack { return smooth(u / attack) }
            if u < attack + hold { return 1 }
            return 1 - smooth((u - attack - hold) / release)
        }
    }

    private var beats: [Beat] = []
    var holdScale: Double = 1          // debug: stretch the peak so it can be screenshotted

    func add(zoom: CGFloat, slow: CGFloat = 1, attack: TimeInterval = 0.06, hold: TimeInterval, release: TimeInterval, at t: TimeInterval) {
        beats.append(Beat(start: t, attack: attack, hold: hold * holdScale, release: release, zoom: zoom, slow: slow))
    }

    func sample(at t: TimeInterval) -> (zoom: CGFloat, slow: CGFloat) {
        beats.removeAll { t > $0.end }
        var zoom: CGFloat = 0, slow: CGFloat = 1
        for b in beats {
            let e = b.envelope(t)
            zoom = max(zoom, b.zoom * e)
            slow = min(slow, 1 - (1 - b.slow) * e)
        }
        return (zoom, slow)
    }
}
