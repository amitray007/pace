import AppKit
@testable import PaceApp
import PaceCore
import Testing

@MainActor
struct RailCompositorBenchmarkTests {
    private func content(_ providerID: ProviderID, buckets: Int) throws -> RailDetailContent {
        let accountID = AccountID(rawValue: UUID())
        let date = Date(timeIntervalSince1970: 0)
        return try RailDetailContent(
            providerID: providerID,
            snapshots: (0 ..< buckets).map { index in
                try LimitSnapshot(
                    providerID: providerID, accountID: accountID,
                    bucketID: BucketID(rawValue: "bucket-\(index)"), label: "Quota \(index)",
                    usedFraction: 0.4, observedAt: date, freshness: .current,
                )
            },
            status: nil, increasedContrast: false, nextRefreshAt: nil,
            isRefreshing: false, referenceDate: date, accountName: "Fixture",
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACE_BENCHMARK_MOTION"] == "1"))
    func `reports compositor keyframe preparation cost`() throws {
        let ids: [ProviderID] = [.claude, .codex, .cursor]
        let contents = try [
            content(.claude, buckets: 2),
            content(.codex, buckets: 3),
            content(.cursor, buckets: 2),
        ]
        func state(_ preview: RailPreviewState) -> RailSurfaceState {
            RailSurfaceState(
                rows: ids.map { RailProviderContent(
                    id: $0,
                    usage: 0.4,
                    status: nil,
                    increasedContrast: false,
                ) },
                contents: contents, preview: preview, edge: .right, reducesMotion: false,
            )
        }

        let view = RailSurfaceView(frame: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize))
        view.update(state(.claude), at: 1)
        for index in 0 ..< 3 {
            view.update(
                state(RailPreviewState(rawValue: ids[index].rawValue) ?? .claude),
                at: Double(index + 2),
            )
        }

        var milliseconds: [Double] = []
        for index in 0 ..< 30 {
            let startedAt = CACurrentMediaTime()
            view.update(
                state(RailPreviewState(rawValue: ids[index % ids.count].rawValue) ?? .claude),
                at: Double(index + 10),
            )
            milliseconds.append((CACurrentMediaTime() - startedAt) * 1000)
        }
        let sorted = milliseconds.sorted()
        func percentile(_ fraction: Double) -> Double {
            sorted[Int((Double(sorted.count - 1) * fraction).rounded(.up))]
        }
        print(String(
            format: "Rail compositor update cost: p50 %.3f ms, p95 %.3f ms, max %.3f ms",
            percentile(0.5),
            percentile(0.95),
            sorted.last ?? 0,
        ))
    }
}
