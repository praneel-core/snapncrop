import Foundation

public struct TouchPoint: Equatable {
    public var x: Float   // 0...1 across the trackpad
    public var y: Float
    public init(x: Float, y: Float) { self.x = x; self.y = y }
}

/// Recognises "four fingers land together, lift quickly, barely move" from raw touch frames.
/// Feed it one call per frame from the trackpad. Returns true on the frame the tap completes.
/// Pure logic (no hardware) so it can be tuned and unit-tested.
public struct FourFingerTapDetector {
    public struct Config {
        /// Max time from the 4th finger landing to the first finger lifting.
        public var maxTapDuration: Double = 0.30
        /// Max time between the first finger and the 4th finger touching ("land together").
        public var maxLandingSpread: Double = 0.15
        /// Max drift of the 4-finger centre, in normalised trackpad units (a swipe moves far more).
        public var maxMovement: Float = 0.04
        /// Ignore re-triggers within this many seconds.
        public var debounce: Double = 0.6
        public init() {}
    }

    public var config: Config
    private var firstContact: Double?
    private var fourthLanding: Double?
    private var startCentre: (x: Float, y: Float)?
    private var invalid = false          // set by 5+ fingers, drift, or holding too long; cleared at 0 fingers
    private var previousCount = 0
    private var lastFire = -Double.infinity

    public init(config: Config = Config()) { self.config = config }

    public mutating func process(_ touches: [TouchPoint], timestamp t: Double) -> Bool {
        let n = touches.count
        defer { previousCount = n }

        if n == 0 {                       // everything lifted: reset
            firstContact = nil; fourthLanding = nil; startCentre = nil
            invalid = false
            return false
        }
        if firstContact == nil { firstContact = t }
        if n > 4 { invalid = true }       // 5th finger or a resting palm: never a deliberate tap

        if n == 4 && fourthLanding == nil && !invalid {
            fourthLanding = t
            startCentre = Self.centre(touches)
        }

        if n == 4, let landed = fourthLanding, !invalid, let start = startCentre {
            let c = Self.centre(touches)
            let drift = max(abs(c.x - start.x), abs(c.y - start.y))
            if drift > config.maxMovement || t - landed > config.maxTapDuration { invalid = true }
        }

        // A finger lifted while we were at exactly four: this is the moment of truth.
        if n < 4 && previousCount == 4, let landed = fourthLanding, !invalid {
            fourthLanding = nil
            invalid = true                // one tap fires once, however the fingers come off
            let together = landed - (firstContact ?? landed) <= config.maxLandingSpread
            let quick = t - landed <= config.maxTapDuration
            if together && quick && t - lastFire > config.debounce {
                lastFire = t
                return true
            }
        }
        return false
    }

    private static func centre(_ pts: [TouchPoint]) -> (x: Float, y: Float) {
        let c = Float(pts.count)
        return (pts.reduce(0) { $0 + $1.x } / c, pts.reduce(0) { $0 + $1.y } / c)
    }
}
