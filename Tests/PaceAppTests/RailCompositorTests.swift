import AppKit
@testable import PaceApp
import PaceCore
import Testing

@MainActor
@Suite("Rail compositor")
struct RailCompositorTests {
    private func content(_ providerID: ProviderID, buckets: Int) throws -> RailDetailContent {
        let accountID = AccountID(rawValue: UUID())
        let date = Date(timeIntervalSince1970: 0)
        let snapshots = try (0 ..< buckets).map { index in
            try LimitSnapshot(
                providerID: providerID,
                accountID: accountID,
                bucketID: BucketID(rawValue: "bucket-\(index)"),
                label: "Quota \(index)",
                usedFraction: 0.4,
                observedAt: date,
                freshness: .current,
            )
        }
        return RailDetailContent(
            providerID: providerID,
            snapshots: snapshots,
            status: nil,
            increasedContrast: false,
            nextRefreshAt: nil,
            isRefreshing: false,
            referenceDate: date,
            accountName: "Fixture",
        )
    }

    private func state(
        _ preview: RailPreviewState,
        contents: [RailDetailContent],
    ) -> RailSurfaceState {
        RailSurfaceState(
            rows: [.claude, .cursor].map {
                RailProviderContent(id: $0, usage: 0.4, status: nil, increasedContrast: false)
            },
            contents: contents,
            preview: preview,
            edge: .right,
            reducesMotion: false,
        )
    }

    @Test func `shell and rail mask use one sampled path sequence`() throws {
        let short = try content(.claude, buckets: 0)
        let tall = try content(.cursor, buckets: 4)
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.mini, contents: [short, tall]), at: 10)
        view.update(state(.cursor, contents: [short, tall]), at: 11)

        let shell = try #require(view.shell
            .animation(forKey: "pace.surface.path") as? CAKeyframeAnimation)
        let mask = try #require(view.railMask
            .animation(forKey: "pace.surface.path") as? CAKeyframeAnimation)
        let shellPaths = try #require(shell.values as? [CGPath])
        let maskPaths = try #require(mask.values as? [CGPath])

        #expect(shellPaths.count == maskPaths.count)
        #expect(shell.keyTimes == mask.keyTimes)
        #expect(shell.duration == mask.duration)
        for index in [0, shellPaths.count / 2, shellPaths.count - 1] {
            #expect(shellPaths[index] == maskPaths[index])
        }
    }

    @Test func `detail keyframes move the fixed-size host inside the matching mask`() throws {
        let short = try content(.claude, buckets: 0)
        let tall = try content(.cursor, buckets: 4)
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.claude, contents: [short, tall]), at: 10)
        view.update(state(.cursor, contents: [short, tall]), at: 11)

        let host = try #require(view.detailViews[.cursor])
        let hostPosition = try #require(host.layer?
            .animation(forKey: "pace.surface.position") as? CAKeyframeAnimation)
        let mask = try #require(view.detailMask
            .animation(forKey: "pace.surface.path") as? CAKeyframeAnimation)
        let maskPaths = try #require(mask.values as? [CGPath])
        let positions = try #require(hostPosition.values as? [NSValue])
        let anchor = try #require(host.layer?.anchorPoint)

        #expect(host.bounds.height == ceil(host.fittingSize.height))
        #expect(hostPosition.keyTimes == mask.keyTimes)
        #expect(positions.count == maskPaths.count)
        #expect(maskPaths.first?.boundingBoxOfPath.height != maskPaths.last?.boundingBoxOfPath
            .height)
        for index in [0, positions.count / 2, positions.count - 1] {
            let position = positions[index].pointValue
            let maskRect = maskPaths[index].boundingBoxOfPath
            // NSHostingView may use a non-default backing-layer anchor. Rebuild
            // the visible frame from that actual anchor rather than assuming a
            // centred layer, then keep its header edge flush with the clip.
            let left = position.x - host.bounds.width * anchor.x
            let top = position.y + host.bounds.height * (1 - anchor.y)
            #expect(abs(left - maskRect.minX) < 0.000_001)
            #expect(abs(top - maskRect.maxY) < 0.000_001)
        }
    }

    @Test func `settings glyph turns around its visible center`() throws {
        let detail = try content(.claude, buckets: 2)
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.claude, contents: [detail]), at: 10)
        view.setSettingsHovered(true, at: 11)
        let layer = try #require(view.settingsGlyph.layer)
        let pivot = CGPoint(
            x: view.settingsGlyph.bounds.width * (0.5 - layer.anchorPoint.x),
            y: view.settingsGlyph.bounds.height * (0.5 - layer.anchorPoint.y),
        )
        for time in [11.0, 11.08, 11.2, 12.0] {
            let transform = try #require(view.sampleLayers(at: time)[layer]?.transform)
            let center = pivot.applying(CATransform3DGetAffineTransform(transform))
            #expect(abs(center.x - pivot.x) < 0.000_001)
            #expect(abs(center.y - pivot.y) < 0.000_001)
        }
    }
}
