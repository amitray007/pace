import AppKit
@testable import PaceApp
import PaceCore
import Testing

@MainActor
struct RailSurfaceTests {
    private func state(
        _ preview: RailPreviewState,
        contents: [RailDetailContent]? = nil,
        edge: RailEdge = .right,
        reduced: Bool = false,
    ) -> RailSurfaceState {
        let ids: [ProviderID] = [.claude, .codex, .cursor]
        return RailSurfaceState(rows: ids.map {
            RailProviderContent(id: $0, usage: 0.4, status: nil, increasedContrast: false)
        }, contents: contents ?? ids.map {
            RailDetailContent(
                providerID: $0,
                snapshots: [],
                status: nil,
                increasedContrast: false,
                nextRefreshAt: nil,
                isRefreshing: false,
                referenceDate: Date(timeIntervalSince1970: 0),
                accountName: "Fixture",
            )
        }, preview: preview, edge: edge, reducesMotion: reduced)
    }

    private func content(buckets: Int) throws -> RailDetailContent {
        let date = Date(timeIntervalSince1970: 0)
        let account = AccountID(rawValue: UUID())
        let snapshots = try (0 ..< buckets).map { index in
            try LimitSnapshot(
                providerID: .cursor,
                accountID: account,
                bucketID: BucketID(rawValue: "bucket-\(index)"),
                label: "Quota \(index)",
                usedFraction: 0.4,
                observedAt: date,
                freshness: .current,
            )
        }
        return RailDetailContent(
            providerID: .cursor,
            snapshots: snapshots,
            status: nil,
            increasedContrast: false,
            nextRefreshAt: nil,
            isRefreshing: false,
            referenceDate: date,
            accountName: "Fixture",
        )
    }

    @Test func `shell and mask stay identical during reveal and reversal`() {
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.mini), at: 10)
        view.update(state(.cursor), at: 11)
        for time in stride(from: 11.0, through: 11.15, by: 1.0 / 120) {
            view.render(at: time)
            #expect(view.shell.path == view.railMask.path)
            #expect(view.detailShell.opacity == view.detailContainer.layer?.opacity)
        }
        let before = view.expansion.sample(at: 11.15)
        view.update(state(.mini), at: 11.15)
        #expect(view.expansion.sample(at: 11.15).value == before.value)
        #expect(view.expansion.sample(at: 11.15).velocity == before.velocity)
        view.render(at: 13)
        #expect(!view.isAnimating(at: 13))
        #expect(view.detailShell.opacity == 0)
    }

    @Test func `provider switch keeps hosts and aligns moving card with input`() {
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        let bridge = RailSurfaceBridge()
        view.bridge = bridge
        view.update(state(.claude), at: 10)
        let host = view.detailViews[.claude]
        view.update(state(.cursor), at: 11)
        view.render(at: 11.09)
        #expect(view.detailViews[.claude] === host)
        #expect(host?.rootView.isActive == false)
        #expect(view.detailViews[.cursor]?.rootView.isActive == true)
        #expect(bridge.detailRect == view.renderedDetailRect)
        #expect(view.detailMask.path?.boundingBoxOfPath == view.viewRect(view.renderedDetailRect))
        let movingCenter = view.detailCenter.sample(at: 11.09)
        view.update(state(.codex), at: 11.09)
        #expect(view.detailCenter.sample(at: 11.09).value == movingCenter.value)
        #expect(view.detailCenter.sample(at: 11.09).velocity == movingCenter.velocity)
        view.update(state(.mini), at: 12)
        #expect(view.detailViews.values.allSatisfy { !$0.rootView.isActive })
    }

    @Test func `reduced motion and left edge use final geometry`() {
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.mini, edge: .left, reduced: true), at: 10)
        view.update(state(.cursor, edge: .left, reduced: true), at: 11)
        #expect(view.expansion.sample(at: 11).value == 1)
        #expect(view.detailCenter.sample(at: 11).velocity == 0)
        view.render(at: 11.2)
        #expect(!view.isAnimating(at: 11.2))
        #expect(view.shell.path?.boundingBoxOfPath.minX == 0)
        #expect(view.detailMask.path?.boundingBoxOfPath == view.viewRect(view.renderedDetailRect))
    }

    @Test func `natural detail height grows through five quotas and clips overflow`() throws {
        let contents = try [0, 1, 3, 5, 7].map { try content(buckets: $0) }
        var heights: [CGFloat] = []
        for (index, content) in contents.enumerated() {
            let view = RailSurfaceView(frame: NSRect(
                origin: .zero,
                size: EdgeRailGeometry.canvasSize,
            ))
            let time = TimeInterval(index * 10)
            view.update(state(.mini, contents: [content]), at: time)
            view.update(state(.cursor, contents: [content]), at: time + 1)
            view.render(at: time + 4)
            let host = try #require(view.detailViews[.cursor])
            let maskHeight = try #require(view.detailMask.path?.boundingBoxOfPath.height)

            heights.append(host.bounds.height)
            #expect(host.rootView.content.snapshots.count == content.snapshots.count)
            #expect(maskHeight == host.bounds.height)
        }

        // Empty content uses the distinct status panel. Quota lists themselves
        // grow naturally through the five-row viewport cap.
        #expect(heights[0] > 0)
        #expect(heights[1] < heights[2])
        #expect(heights[2] < heights[3])
        #expect(heights[3] == heights[4])
    }

    @Test func `same provider shrinking restores its natural detail height`() throws {
        let one = try content(buckets: 1)
        let five = try content(buckets: 5)
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.cursor, contents: [one]), at: 10)
        view.render(at: 14)
        let host = try #require(view.detailViews[.cursor])
        let originalHeight = host.bounds.height

        view.update(state(.cursor, contents: [five]), at: 15)
        view.render(at: 19)
        #expect(host.bounds.height > originalHeight)

        view.update(state(.cursor, contents: [one]), at: 20)
        view.render(at: 24)
        #expect(host.bounds.height == originalHeight)
        #expect(view.renderedDetailRect.height == originalHeight)
        #expect(view.detailMask.path?.boundingBoxOfPath.height == originalHeight)
    }

    @Test func `enabling reduced motion interrupts geometric movement immediately`() {
        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.mini), at: 10)
        view.update(state(.cursor), at: 11)
        view.render(at: 11.04)
        view.update(state(.cursor, reduced: true), at: 11.04)
        #expect(view.expansion.sample(at: 11.04).value == 1)
        #expect(view.rowViews[.cursor]?.layer?.affineTransform().tx == 0)
        view.render(at: 11.2)
        #expect(!view.isAnimating(at: 11.2))
    }
}
