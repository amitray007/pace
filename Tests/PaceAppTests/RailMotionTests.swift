@testable import PaceApp
import Testing

@MainActor
@Suite("Rail motion and geometry")
struct RailMotionTests {
    @Test func `reversal inherits the visible value and velocity`() {
        var track = RailMotion.Track(0)
        track.retarget(1, at: 0, curve: .spring(RailMotion.unfoldSpring))
        let beforeReversal = track.sample(at: 0.12)

        track.retarget(0, at: 0.12, curve: .spring(RailMotion.unfoldSpring))
        let atReversal = track.sample(at: 0.12)

        #expect(abs(atReversal.value - beforeReversal.value) < 0.000_001)
        #expect(abs(atReversal.velocity - beforeReversal.velocity) < 0.000_001)
    }

    @Test func `interrupted reversal follows through and settles`() {
        var track = RailMotion.Track(0)
        track.retarget(1, at: 0, curve: .spring(RailMotion.unfoldSpring))
        track.retarget(0, at: 0.12, curve: .spring(RailMotion.unfoldSpring))

        let immediatelyAfter = track.sample(at: 0.121)
        let settled = track.sample(at: 5)

        #expect(immediatelyAfter.value > 0)
        #expect(abs(settled.value) < 0.000_001)
        #expect(abs(settled.velocity) < 0.000_001)
        #expect(!track.isActive(at: 5))
    }

    @Test func `repeated target does not restart A reading`() {
        var repeated = RailMotion.Track(0)
        var control = RailMotion.Track(0)
        repeated.retarget(1, at: 0, curve: .spring(RailMotion.contentSpring))
        control.retarget(1, at: 0, curve: .spring(RailMotion.contentSpring))

        repeated.retarget(1, at: 0.08, curve: .spring(RailMotion.contentSpring))
        let expected = control.sample(at: 0.16)
        let actual = repeated.sample(at: 0.16)

        #expect(abs(actual.value - expected.value) < 0.000_001)
        #expect(abs(actual.velocity - expected.velocity) < 0.000_001)
    }

    @Test func `delayed stagger reversal does not jump`() {
        var track = RailMotion.Track(0)
        track.retarget(
            1,
            at: 0,
            curve: .spring(RailMotion.contentSpring),
            delay: 0.18,
        )
        let beforeReversal = track.sample(at: 0.08)
        track.retarget(0, at: 0.08, curve: .spring(RailMotion.contentSpring))
        let atReversal = track.sample(at: 0.08)

        #expect(beforeReversal.value == 0)
        #expect(beforeReversal.velocity == 0)
        #expect(atReversal.value == beforeReversal.value)
        #expect(atReversal.velocity == beforeReversal.velocity)
        #expect(!track.isActive(at: 0.081))
    }

    @Test func `reduced motion retargets directly`() {
        var track = RailMotion.Track(0)
        track.retarget(1, at: 0, curve: .spring(RailMotion.unfoldSpring))
        track.retarget(
            0.4,
            at: 0.1,
            curve: .fade(RailMotion.reducedMotionFadeDuration),
            directly: true,
        )
        let sampled = track.sample(at: 0.1)

        #expect(sampled.value == 0.4)
        #expect(sampled.velocity == 0)
        #expect(!track.isActive(at: 0.1))
    }

    @Test func `geometry does not share provider row count between renders`() {
        let shortRail = RailShellMetrics.settingsCircleRect(providerRowCount: 1)
        let longRail = RailShellMetrics.settingsCircleRect(providerRowCount: 5)
        let shortAgain = RailShellMetrics.settingsCircleRect(providerRowCount: 1)

        #expect(longRail.midY > shortRail.midY)
        #expect(shortAgain == shortRail)
    }

    @Test func `settings and shell use the same instance geometry`() {
        let rows = 4
        let arc = RailShellMetrics.settingsArcCenter(providerRowCount: rows)
        let circle = RailShellMetrics.settingsCircleRect(providerRowCount: rows)

        #expect(circle.midX == arc.x)
        #expect(circle.midY == arc.y)
    }
}
