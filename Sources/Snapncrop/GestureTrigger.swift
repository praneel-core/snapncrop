import Foundation
import SnapncropCore

/// Anything that can fire a capture from a physical gesture. Isolated behind a protocol so a
/// broken private API can be switched off (or replaced) without touching the rest of the app.
protocol GestureTrigger: AnyObject {
    var onTrigger: (() -> Void)? { get set }
    /// Called (on the main queue) whenever the number of fingers on the trackpad changes. For tuning.
    var onFingerCount: ((Int) -> Void)? { get set }
    @discardableResult func start() -> Bool
    func stop()
}

// MARK: - MultitouchSupport (private Apple framework)
//
// This framework is private: Apple can change it in any macOS update. We therefore
//  * load it at runtime with dlopen (so a missing framework can never stop the app launching),
//  * only ever READ touch frames (we never block or consume the system's own gestures),
//  * treat any failure as "gesture unavailable" and carry on with the hotkey.

private typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
private typealias MTStartStopFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTStopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

/// Memory layout of one MTTouch record as delivered by MultitouchSupport (stable since ~2010).
private enum MTTouchLayout {
    static let stride = 96
    static let stateOffset = 20      // Int32: 3 = making contact, 4 = touching, 5 = breaking, 7 = out of range
    static let xOffset = 32          // Float32, normalised 0...1
    static let yOffset = 36          // Float32
}

final class MultitouchGestureTrigger: GestureTrigger {
    var onTrigger: (() -> Void)?
    var onFingerCount: ((Int) -> Void)?

    // The C callback cannot capture context, so it reaches us through this global.
    fileprivate static var current: MultitouchGestureTrigger?

    private let lock = NSLock()
    private var detectors: [UnsafeMutableRawPointer: FourFingerTapDetector] = [:]
    private var lastCount = -1
    private var devices: [UnsafeMutableRawPointer] = []
    private var running = false

    private var unregisterFn: MTRegisterFn?
    private var stopFn: MTStopFn?

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let listSym = dlsym(lib, "MTDeviceCreateList"),
              let regSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart")
        else { Log.gesture.error("MultitouchSupport unavailable; four-finger tap disabled"); return false }

        let createList = unsafeBitCast(listSym, to: MTDeviceCreateListFn.self)
        let register = unsafeBitCast(regSym, to: MTRegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: MTStartStopFn.self)
        unregisterFn = dlsym(lib, "MTUnregisterContactFrameCallback").map { unsafeBitCast($0, to: MTRegisterFn.self) }
        stopFn = dlsym(lib, "MTDeviceStop").map { unsafeBitCast($0, to: MTStopFn.self) }

        guard let list = createList()?.takeRetainedValue() else {
            Log.gesture.error("no multitouch devices"); return false
        }
        MultitouchGestureTrigger.current = self
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            register(dev, mtFrameCallback)
            startDevice(dev, 0)
            devices.append(dev)
        }
        // Keep the CFArray (and so the devices) alive for as long as we run.
        retainedList = list
        running = !devices.isEmpty
        Log.gesture.info("started on \(self.devices.count) multitouch device(s)")
        return running
    }

    private var retainedList: CFArray?

    func stop() {
        guard running else { return }
        for dev in devices {
            unregisterFn?(dev, mtFrameCallback)      // same signature as register; harmless if absent
            stopFn?(dev)
        }
        devices.removeAll(); retainedList = nil
        lock.lock(); detectors.removeAll(); lock.unlock()
        running = false
        MultitouchGestureTrigger.current = nil
    }

    /// Runs on a private MultitouchSupport thread.
    fileprivate func handle(device: UnsafeMutableRawPointer, data: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        var points: [TouchPoint] = []
        if let data, count > 0 {
            for i in 0..<count {
                let base = data + i * MTTouchLayout.stride
                let state = base.load(fromByteOffset: MTTouchLayout.stateOffset, as: Int32.self)
                guard state == 3 || state == 4 else { continue }       // only fingers actually on the glass
                points.append(TouchPoint(x: base.load(fromByteOffset: MTTouchLayout.xOffset, as: Float.self),
                                         y: base.load(fromByteOffset: MTTouchLayout.yOffset, as: Float.self)))
            }
        }
        lock.lock()
        var det = detectors[device] ?? FourFingerTapDetector()
        let fired = det.process(points, timestamp: timestamp)
        detectors[device] = det
        let changed = points.count != lastCount
        lastCount = points.count
        lock.unlock()

        if changed { let n = points.count; DispatchQueue.main.async { self.onFingerCount?(n) } }
        if fired { DispatchQueue.main.async { Log.gesture.info("four-finger tap"); self.onTrigger?() } }
    }
}

private func mtFrameCallback(_ device: UnsafeMutableRawPointer?, _ data: UnsafeMutableRawPointer?,
                             _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    if let device { MultitouchGestureTrigger.current?.handle(device: device, data: data, count: Int(count), timestamp: timestamp) }
    return 0
}
