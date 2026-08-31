import Foundation
@testable import PaceCore
import Testing

@Suite("Rail activation engine")
struct RailActivationEngineTests {
    @Test
    func `modifier hover reveals only with deliberate combined intent`() {
        var engine = makeEngine(mode: .modifierHover)

        #expect(engine.handle(.modifierChanged(isActive: true), at: 1).isEmpty)
        #expect(engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 2) == [.reveal])
        #expect(engine.phase == .revealed)
    }

    @Test
    func `dwell hover waits for its configured deadline`() {
        var engine = makeEngine(mode: .dwellHover, dwellDelay: 0.6)

        #expect(engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 1).isEmpty)
        #expect(engine.phase == .intentPending)
        #expect(engine.handle(.tick, at: 1.59).isEmpty)
        #expect(engine.handle(.tick, at: 1.6) == [.reveal])
    }

    @Test
    func `repeated input snapshots do not reset pending deadlines`() {
        var engine = makeEngine(mode: .dwellHover, dwellDelay: 0.6)

        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 1)
        _ = engine.handle(.modifierChanged(isActive: false), at: 1.2)
        _ = engine.handle(.mouseButtonsChanged(isDown: false), at: 1.4)

        #expect(engine.handle(.tick, at: 1.6) == [.reveal])
    }

    @Test
    func `scroll drag and fast edge motion suppress accidental activation`() {
        var engine = makeEngine(mode: .dwellHover, dwellDelay: 0.2)
        _ = engine.handle(.scroll, at: 1)
        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 1.1)
        #expect(engine.handle(.tick, at: 1.5).isEmpty)

        _ = engine.handle(.mouseButtonsChanged(isDown: true), at: 2)
        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 105)), at: 2.1)
        #expect(engine.handle(.tick, at: 2.5).isEmpty)
        _ = engine.handle(.mouseButtonsChanged(isDown: false), at: 2.6)
        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 110)), at: 2.7)
        #expect(engine.handle(.tick, at: 3).isEmpty)

        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 4)
        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 300)), at: 4.1)
        #expect(engine.handle(.tick, at: 4.5).isEmpty)
    }

    @Test
    func `click mode ignores hover and accepts only the handle click`() {
        var engine = makeEngine(mode: .clickHandle)

        _ = engine.handle(.pointerMoved(hotspot(verticalPosition: 100)), at: 1)
        #expect(engine.handle(.tick, at: 10).isEmpty)
        #expect(engine.handle(.primaryClick(region: .outside), at: 11).isEmpty)
        #expect(engine.handle(.primaryClick(region: .hotspot), at: 12) == [.reveal])
    }

    @Test
    func `safe travel cancels dismissal and provider hover is delayed`() {
        var engine = makeEngine(mode: .clickHandle, dismissalDelay: 0.4)
        _ = engine.handle(.primaryClick(region: .hotspot), at: 1)
        _ = engine.handle(
            .pointerMoved(sample(region: .rail(providerIndex: 1))),
            at: 2,
        )
        #expect(engine.handle(.tick, at: 2.07).isEmpty)
        #expect(engine.handle(.tick, at: 2.08) == [.selectProvider(index: 1)])

        _ = engine.handle(.pointerMoved(sample(region: .outside)), at: 3)
        #expect(engine.phase == .dismissalPending)
        _ = engine.handle(.pointerMoved(sample(region: .travelCorridor)), at: 3.2)
        #expect(engine.phase == .revealed)
        #expect(engine.handle(.tick, at: 4).isEmpty)
    }

    @Test
    func `dismissal and availability changes collapse deterministically`() {
        var engine = makeEngine(mode: .clickHandle, dismissalDelay: 0.4)
        _ = engine.handle(.primaryClick(region: .hotspot), at: 1)
        _ = engine.handle(.pointerMoved(sample(region: .outside)), at: 2)
        #expect(engine.handle(.tick, at: 2.39).isEmpty)
        #expect(engine.handle(.tick, at: 2.4) == [.dismiss])

        _ = engine.handle(.primaryClick(region: .hotspot), at: 3)
        #expect(
            engine.handle(.fullScreenChanged(isExcluded: true), at: 4) == [.dismiss],
        )
    }

    @Test
    func `provider clicks and settings clicks are immediate while revealed`() {
        var engine = makeEngine(mode: .clickHandle)
        _ = engine.handle(.primaryClick(region: .hotspot), at: 1)

        #expect(
            engine.handle(.primaryClick(region: .rail(providerIndex: 2)), at: 2)
                == [.selectProvider(index: 2)],
        )
        #expect(
            engine.handle(.primaryClick(region: .settings), at: 3) == [.openSettings],
        )
    }

    @Test
    func `external presentation changes keep interaction phase aligned`() {
        var engine = makeEngine(mode: .modifierHover)

        engine.synchronizePresentation(isRevealed: true)
        #expect(engine.phase == .revealed)
        engine.synchronizePresentation(isRevealed: false)
        #expect(engine.phase == .collapsed)
    }

    private func makeEngine(
        mode: RailActivationMode,
        dwellDelay: TimeInterval = 0.6,
        dismissalDelay: TimeInterval = 0.4,
    ) -> RailActivationEngine {
        RailActivationEngine(
            configuration: RailActivationConfiguration(
                mode: mode,
                dwellDelay: dwellDelay,
                dismissalDelay: dismissalDelay,
            ),
        )
    }

    private func hotspot(verticalPosition: Double) -> RailPointerSample {
        RailPointerSample(
            horizontalPosition: 0,
            verticalPosition: verticalPosition,
            region: .hotspot,
        )
    }

    private func sample(region: RailPointerRegion) -> RailPointerSample {
        RailPointerSample(horizontalPosition: 0, verticalPosition: 0, region: region)
    }
}
