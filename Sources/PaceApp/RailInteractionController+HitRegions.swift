import AppKit
import PaceCore

/// The pointer's hit regions and the input panels' frames.
///
/// Every rect here is derived from the same top-down authored geometry the
/// shell draws from, so the visible and interactive rail cannot drift apart.
extension RailInteractionController {
    /// How many provider rows the rail is showing, which the hit regions are
    /// laid out against.
    private var railProviderCount: Int {
        min(model.visibleProviderIDs.count, EdgeRailGeometry.maximumProviderRows)
    }

    var interactionTargets: [(frame: NSRect, accessibilityLabel: String?)] {
        if model.railPreviewState == .mini {
            return model.preferences.activationMode == .clickHandle
                ? [(hotspotFrame, "Open Pace rail")]
                : []
        }
        return [(railFrame, nil), (settingsFrame, nil)] +
            (detailFrame.map { [($0, nil)] } ?? [])
    }

    func pointerRegion(at location: NSPoint) -> RailPointerRegion {
        if model.railPreviewState == .mini {
            return collapsedPointerFrame.contains(location) ? .hotspot : .outside
        }
        if settingsFrame.contains(location) {
            return .settings
        }
        for (index, frame) in providerFrames.enumerated() where frame.contains(location) {
            return .rail(providerIndex: index)
        }
        if railFrame.contains(location) {
            return .rail(providerIndex: nil)
        }
        if detailFrame?.contains(location) == true {
            return .detail
        }
        if travelCorridorFrame?.contains(location) == true {
            return .travelCorridor
        }
        return .outside
    }

    /// Converts a rect authored in the shell's top-down canvas coordinates
    /// into the on-screen rect the pointer actually meets: flipped like the
    /// layer view flips its paths, mirrored for the left edge, and scaled
    /// around the screen edge. Hit regions must take the same trip the drawing
    /// takes; the collapsed handle's hotspot once skipped the flip and sat
    /// 150 pt below the visible handle, which made hovering it feel
    /// impossible.
    private func interactionFrame(authored rect: CGRect) -> NSRect {
        guard let visualPanel else {
            return .zero
        }
        let canvas = EdgeRailGeometry.canvasSize
        let originX = model.preferences.railEdge == .right
            ? rect.minX
            : canvas.width - rect.maxX
        return scaledInteractionFrame(NSRect(
            x: visualPanel.frame.minX + originX,
            y: visualPanel.frame.minY + canvas.height - rect.maxY,
            width: rect.width,
            height: rect.height,
        ))
    }

    /// The collapsed handle's pointer target.
    ///
    /// Derived from the same rect the shell draws the handle from, so shrinking
    /// the handle cannot leave the clickable area somewhere else. The target is
    /// deliberately larger than the visible handle, which stays small.
    private var hotspotFrame: NSRect {
        interactionFrame(authored: RailShellMetrics.handleTargetRect)
    }

    /// The hover modes' pointer target: the edge band the rail opens into.
    ///
    /// Hover activation has no input window, so the larger band cannot block
    /// clicks, scrolling, or drags. Click mode keeps the small handle target,
    /// because that one backs a real input panel.
    private var hoverHotspotFrame: NSRect {
        interactionFrame(authored: RailShellMetrics.hoverTargetRect)
    }

    private var collapsedPointerFrame: NSRect {
        model.preferences.activationMode == .clickHandle ? hotspotFrame : hoverHotspotFrame
    }

    private var railFrame: NSRect {
        interactionFrame(authored: NSRect(
            x: EdgeRailGeometry.railOriginX,
            y: RailShellMetrics.topEdgeY,
            width: EdgeRailGeometry.railWidth,
            height: RailShellMetrics.bottomEdgeY - RailShellMetrics.topEdgeY,
        ))
    }

    private var providerFrames: [NSRect] {
        EdgeRailGeometry.providerTopY(count: railProviderCount).map { topPosition in
            interactionFrame(authored: NSRect(
                x: EdgeRailGeometry.railOriginX,
                y: topPosition,
                width: EdgeRailGeometry.railWidth,
                height: 64,
            ))
        }
    }

    private var settingsFrame: NSRect {
        let center = RailShellMetrics.settingsCircleCenter
        return interactionFrame(authored: NSRect(
            x: center.x - 23,
            y: center.y - 23,
            width: 46,
            height: 46,
        ))
    }

    /// The drawn detail panel's frame, sized the same way EdgeRailView sizes
    /// it so the hit region hugs the drawn panel.
    private var detailFrame: NSRect? {
        guard let detailCenterY else {
            return nil
        }
        let quotaCount = model.railPreviewState.detailProviderID
            .flatMap { providerID in model.selectedAccount(for: providerID) }
            .map { account in model.snapshots(for: account.id).count } ?? 0
        let height = EdgeRailGeometry.detailHeight(quotaCount: quotaCount)
        return interactionFrame(authored: NSRect(
            x: 0,
            y: EdgeRailGeometry.detailPanelY(centerY: detailCenterY, height: height),
            width: EdgeRailGeometry.detailWidth,
            height: height,
        ))
    }

    private var travelCorridorFrame: NSRect? {
        guard let detailFrame, let detailCenterY,
              let providerIndex = EdgeRailGeometry.providerCentersY(count: railProviderCount)
                  .firstIndex(of: detailCenterY),
                  providerFrames.indices.contains(providerIndex)
        else {
            return nil
        }
        let centerY = providerFrames[providerIndex].midY
        let minimumX = model.preferences.railEdge == .right ? detailFrame.maxX : railFrame.maxX
        let maximumX = model.preferences.railEdge == .right ? railFrame.minX : detailFrame.minX
        return NSRect(
            x: minimumX,
            y: centerY - 24,
            width: max(maximumX - minimumX, 0),
            height: 48,
        )
    }

    private func scaledInteractionFrame(_ frame: NSRect) -> NSRect {
        guard let visualPanel else {
            return .zero
        }
        let scale = EdgeRailGeometry.displayScale(for: model.preferences)
        let anchorX = model.preferences.railEdge == .right
            ? visualPanel.frame.maxX
            : visualPanel.frame.minX
        let anchorY = visualPanel.frame.midY
        return NSRect(
            x: anchorX + (frame.minX - anchorX) * scale,
            y: anchorY + (frame.minY - anchorY) * scale,
            width: frame.width * scale,
            height: frame.height * scale,
        )
    }

    private var detailCenterY: CGFloat? {
        guard let providerID = model.railPreviewState.detailProviderID,
              let index = Array(model.visibleProviderIDs
                  .prefix(EdgeRailGeometry.maximumProviderRows)).firstIndex(of: providerID),
              EdgeRailGeometry.providerCentersY(count: railProviderCount).indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY(count: railProviderCount)[index]
    }

    static func configuration(for preferences: PacePreferences)
    -> RailActivationConfiguration {
        RailActivationConfiguration(
            mode: preferences.activationMode,
            dwellDelay: preferences.dwellDelay,
            dismissalDelay: preferences.dismissalDelay,
        )
    }
}
