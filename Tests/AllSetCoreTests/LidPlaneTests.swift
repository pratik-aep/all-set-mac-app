import Foundation
import Testing
@testable import AllSetCore

// Ported from Lid Plane (c) 2026 Jhey, GPL-3.0-or-later.
@Suite struct LidPlaneAutoAnchorTests {
    @Test func waitsForPauseThenEasesToNewAngle() {
        var state = AutoAnchor(angle: 110, now: 0)
        #expect(state.delay == 0.15 && state.duration == 0.2)
        state.update(angle: 80, now: 0.1, enabled: true)
        state.update(angle: 80, now: 0.24, enabled: true)
        #expect(state.reference == 110)
        state.update(angle: 80, now: 0.251, enabled: true)
        state.update(angle: 80, now: 0.351, enabled: true)
        #expect(abs(state.reference - 95) < 0.01)
        state.update(angle: 80, now: 0.46, enabled: true)
        #expect(state.reference == 80)
    }

    @Test func movementInterruptsSettling() {
        var state = AutoAnchor(angle: 110, now: 0)
        state.update(angle: 80, now: 0.1, enabled: true)
        state.update(angle: 80, now: 0.251, enabled: true)
        state.update(angle: 80, now: 0.301, enabled: true)
        let reference = state.reference
        state.update(angle: 70, now: 0.32, enabled: true)
        state.update(angle: 70, now: 0.46, enabled: true)
        #expect(state.reference == reference)
    }

    @Test func slowCumulativeMovementRestartsDebounce() {
        var state = AutoAnchor(angle: 110, now: 0)
        for i in 1...10 { state.update(angle: 110 - Double(i), now: Double(i) * 0.3, enabled: true) }
        #expect(state.reference == 110)
    }

    @Test func smallSensorJitterDoesNotPreventSettling() {
        var state = AutoAnchor(angle: 110, now: 0)
        state.update(angle: 80, now: 0.1, enabled: true)
        for i in 2...20 { state.update(angle: 80 + (i.isMultiple(of: 2) ? 0.3 : -0.3), now: Double(i) * 0.1, enabled: true) }
        #expect(abs(state.reference - 80) < 0.4)
    }

    @Test func disabledModeHoldsReferenceAndManualAnchorResets() {
        var state = AutoAnchor(angle: 110, now: 0)
        state.update(angle: 70, now: 1, enabled: false)
        state.update(angle: 70, now: 10, enabled: false)
        #expect(state.reference == 110)
        state.anchor(at: 70, now: 11)
        state.update(angle: 60, now: 11.1, enabled: true)
        #expect(state.reference == 70)
    }
}

@Suite struct LidPlaneMotionPolicyTests {
    @Test func captureOnlyWhileAVisibleEffectIsNeeded() {
        #expect(!CaptureDemand.needsCapture(delta: 0, blur: true, warp: true))
        #expect(!CaptureDemand.needsCapture(delta: 0.002, blur: true, warp: true))
        #expect(CaptureDemand.needsCapture(delta: 0.01, blur: true, warp: false))
        #expect(CaptureDemand.needsCapture(delta: -0.01, blur: false, warp: true))
        #expect(!CaptureDemand.needsCapture(delta: 0.1, blur: false, warp: false))
        #expect(!CaptureDemand.needsCapture(delta: .nan, blur: true, warp: true))
    }

    @Test func absoluteActivationAndJitter() {
        #expect(LidPlaneDefaults.activationAngle == 110 && LidPlaneDefaults.jitterTolerance == 0)
        #expect(AngleActivation.allows(angle: 110, limit: 110, enabled: true))
        #expect(!AngleActivation.allows(angle: 110.01, limit: 110, enabled: true))
        #expect(AngleActivation.allows(angle: 120, limit: 90, enabled: false))
        #expect(!AngleActivation.allows(angle: .nan, limit: 90, enabled: false))
        var filter = LidMotionFilter()
        filter.reset(to: 110)
        let r1 = filter.update(109.9, tolerance: 0)
        #expect(r1 == 109.9)
        filter.reset(to: 110)
        for value in [109.0, 111, 108, 112, 109, 111] {
            let held = filter.update(value, tolerance: 2)
            #expect(held == 110)
        }
        // Slow movement accumulates instead of being swallowed.
        let r2 = filter.update(107, tolerance: 2)
        #expect(r2 == 107)
        let r3 = filter.update(106, tolerance: 1)
        #expect(r3 == 107)
        let r4 = filter.update(105, tolerance: 1)
        #expect(r4 == 105)
        // A stale filtered value can never bypass the raw cut-off.
        #expect(!AngleActivation.allows(angle: 91, limit: 90, enabled: true))
    }

    @Test func displaySafetyNeverFallsBackToAnExternalScreen() {
        var safety = DisplaySafetyGate()
        let r5 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 0)
        #expect(!r5)
        let r6 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 0.51)
        #expect(r6)
        let r7 = safety.update(lidClosed: true, builtInAvailable: true, sensorAvailable: true, now: 1)
        #expect(!r7)
        #expect(safety.state == .closed)
        let r8 = safety.update(lidClosed: false, builtInAvailable: false, sensorAvailable: true, now: 2)
        #expect(!r8)
        #expect(safety.state == .noDisplay)
        let r9 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: false, now: 3)
        #expect(!r9)
        #expect(safety.state == .noSensor)
        let r10 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4)
        #expect(!r10)
        let r11 = safety.update(lidClosed: false, builtInAvailable: false, sensorAvailable: true, now: 4.3)
        #expect(!r11)
        let r12 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.4)
        #expect(!r12)
        let r13 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.8)
        #expect(!r13)
        let r14 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.91)
        #expect(r14)
        safety.reset()
        let r15 = safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 5)
        #expect(!r15)
    }
}

@Suite @MainActor struct LidPlaneSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AllSetTests-lidplane-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsOffWithTheRecommendedBehaviour() {
        let settings = LidPlaneSettings(defaults: freshDefaults())
        #expect(!settings.isEnabled && settings.angleMode)
        #expect(settings.activationAngle == 110 && settings.jitterTolerance == 0)
        #expect(settings.blur && settings.holdAngle && settings.perspective && settings.shortcutEnabled)
    }

    @Test func choicesSurviveARelaunchAndStayInRange() {
        let defaults = freshDefaults()
        let first = LidPlaneSettings(defaults: defaults)
        first.isEnabled = true
        first.angleMode = false
        first.activationAngle = 95
        first.perspective = false
        defaults.set(999.0, forKey: "lidplane.jitterTolerance")
        let second = LidPlaneSettings(defaults: defaults)
        #expect(second.isEnabled && !second.angleMode && second.activationAngle == 95 && !second.perspective)
        #expect(second.jitterTolerance == LidPlaneSettings.jitterRange.upperBound)
        second.resetBehaviour()
        #expect(second.isEnabled && second.angleMode && second.activationAngle == 110 && second.perspective)
    }
}
