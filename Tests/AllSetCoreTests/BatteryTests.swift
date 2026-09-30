import Foundation
import Testing
@testable import AllSetCore

@Suite struct BatteryTests {
    /// Settings saved before the option existed rest on battery, the new default.
    @Test func tapTapRestsOnBatteryUnlessTurnedOff() throws {
        let old = try JSONDecoder().decode(KnockSettings.self, from: Data(#"{"isEnabled": true, "restInLowPowerMode": true}"#.utf8))
        #expect(old.restOnBattery)
        var settings = KnockSettings()
        settings.restOnBattery = false
        let again = try JSONDecoder().decode(KnockSettings.self, from: JSONEncoder().encode(settings))
        #expect(!again.restOnBattery)
    }

    @Test func idleSamplingSlowsOffTheCharger() {
        #expect(PerformancePolicy(isOnBattery: true).monitorIdleInterval > PerformancePolicy().monitorIdleInterval)
        #expect(PerformancePolicy(isOnBattery: true).artFrameRate < PerformancePolicy().artFrameRate)
    }
}
