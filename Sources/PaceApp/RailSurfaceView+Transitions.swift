import Foundation

extension RailSurfaceView {
    func retargetRows(_ next: RailSurfaceState, initial: Bool, at time: TimeInterval) {
        let expanded = next.preview != .mini
        let curve: RailMotion.Curve = next
            .reducesMotion ? .fade(0.1) : .spring(RailMotion.contentSpring)
        for (index, row) in next.rows.enumerated() {
            if rowTracks[row.id] == nil {
                rowTracks[row.id] = RailMotion.Track(initial && expanded ? 1 : 0)
            }
            let delay = expanded && !next.reducesMotion ? min(Double(index) * 0.045, 0.18) : 0
            let restart = next.reducesMotion && rowTracks[row.id]?.isActive(at: time) == true
            rowTracks[row.id]?.retarget(
                expanded ? 1 : 0,
                at: time,
                curve: curve,
                delay: delay,
                directly: initial,
                restart: restart,
            )
        }
    }

    func retargetDetail(
        _ next: RailSurfaceState,
        previous: RailSurfaceState?,
        at time: TimeInterval,
    ) {
        let selected = next.preview.detailProviderID
        let initial = previous == nil
        let fade: RailMotion.Curve = .fade(next.reducesMotion ? 0.1 : 0.16)
        retargetDetailGeometry(next, previous: previous, at: time)
        let restartFade = next.reducesMotion && detailPresence.isActive(at: time)
        detailPresence.retarget(
            selected == nil ? 0 : 1,
            at: time,
            curve: fade,
            directly: initial,
            restart: restartFade,
        )
        for content in next.contents {
            let id = content.providerID
            if contentTracks[id] == nil {
                contentTracks[id] = RailMotion.Track(0)
            }
            // Preserve the outgoing contents while the whole card fades on dismissal.
            if selected != nil || initial {
                let direct = initial || previous?.preview.detailProviderID == nil
                let restart = next.reducesMotion && contentTracks[id]?.isActive(at: time) == true
                contentTracks[id]?.retarget(
                    id == selected ? 1 : 0,
                    at: time,
                    curve: fade,
                    directly: direct,
                    restart: restart,
                )
            }
        }
    }

    private func retargetDetailGeometry(
        _ next: RailSurfaceState,
        previous: RailSurfaceState?,
        at time: TimeInterval,
    ) {
        guard let selected = next.preview.detailProviderID else { return }
        guard let index = next.rows.firstIndex(where: { $0.id == selected }) else { return }
        guard let host = detailViews[selected] else { return }
        let firstDetail = previous?.preview.detailProviderID == nil && detailPresence
            .sample(at: time).value < 0.01
        let direct = previous == nil || next.reducesMotion || firstDetail
        let center = EdgeRailGeometry.providerCentersY(count: next.rows.count)[index]
        detailCenter.retarget(
            center,
            at: time,
            curve: .spring(RailMotion.glideSpring),
            directly: direct,
        )
        detailHeight.retarget(
            host.bounds.height,
            at: time,
            curve: .spring(RailMotion.glideSpring),
            directly: direct,
        )
    }

    func retargetOrb(_ next: RailSurfaceState, initial: Bool, at time: TimeInterval) {
        let expanded = next.preview != .mini
        let normalCurve: RailMotion.Curve = expanded ? .spring(RailMotion.contentSpring) : .merge
        let curve: RailMotion.Curve = next.reducesMotion ? .fade(0.1) : normalCurve
        let delay = expanded && !next.reducesMotion ? min(Double(next.rows.count) * 0.045, 0.18) : 0
        let restart = next.reducesMotion && orbPresence.isActive(at: time)
        orbPresence.retarget(
            expanded ? 1 : 0,
            at: time,
            curve: curve,
            delay: delay,
            directly: initial,
            restart: restart,
        )
        if !expanded {
            requestedSettingsHover = false
        }
        settingsHover.retarget(
            requestedSettingsHover ? 1 : 0,
            at: time,
            curve: .spring(RailMotion.settingsSpring),
            directly: initial || next.reducesMotion,
        )
    }
}
