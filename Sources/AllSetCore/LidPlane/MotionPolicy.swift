// Copyright (c) 2026 Jhey
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A dead band measured from the last accepted angle, not the last raw sample.
/// Small shakes are ignored; gradual movement still accumulates past tolerance.
public struct LidMotionFilter {
    public private(set) var angle: Double?
    public init() {}
    public mutating func reset(to angle: Double) { self.angle = angle }
    public mutating func update(_ sample: Double, tolerance: Double) -> Double {
        guard sample.isFinite else { return angle ?? 0 }
        if angle == nil || abs(sample - angle!) > max(0, tolerance) { angle = sample }
        return angle!
    }
}

/// An absolute lid-angle ceiling. Raw angle is checked first so filtering can
/// never leave the effect visible above the user's selected limit.
public enum AngleActivation {
    public static func allows(angle: Double, limit: Double, enabled: Bool) -> Bool {
        angle.isFinite && (!enabled || angle <= limit)
    }
}

/// Match the renderer's visibility threshold; aligned content needs no stream.
public enum CaptureDemand {
    public static func needsCapture(delta: Float, blur: Bool, warp: Bool) -> Bool {
        delta.isFinite && abs(delta) > 0.002 && (blur || warp)
    }
}

/// Fail closed, then wait for a stable display before restarting capture.
/// No display IDs or UI objects here: topology transitions are deterministic tests.
public struct DisplaySafetyGate {
    public enum State: String {
        case closed = "Paused · lid closed"
        case noDisplay = "Paused · built-in display unavailable"
        case noSensor = "Paused · sensor unavailable"
        case recovering = "Waiting for built-in display…"
        case ready = "Ready"
    }
    public private(set) var state: State = .recovering
    public var recoveryDelay: TimeInterval = 0.5
    private var readySince: TimeInterval?
    public init() {}
    public mutating func reset() { readySince = nil; state = .recovering }
    @discardableResult
    public mutating func update(lidClosed: Bool, builtInAvailable: Bool, sensorAvailable: Bool, now: TimeInterval) -> Bool {
        if lidClosed { state = .closed }
        else if !builtInAvailable { state = .noDisplay }
        else if !sensorAvailable { state = .noSensor }
        else {
            if readySince == nil { readySince = now }
            state = now - readySince! >= recoveryDelay ? .ready : .recovering
            return state == .ready
        }
        readySince = nil
        return false
    }
}
