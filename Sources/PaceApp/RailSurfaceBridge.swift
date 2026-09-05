import AppKit

/// Connects one visual surface to its input windows on the main actor.
/// Rectangles use the renderer's top-down canvas coordinates before scaling.
@MainActor
final class RailSurfaceBridge {
    var detailRect: CGRect?
    var detailCenterY: CGFloat?
    var geometryDidChange: (() -> Void)?
    weak var surface: RailSurfaceView?

    func setSettingsHovered(_ hovered: Bool) {
        surface?.setSettingsHovered(hovered)
    }

    func scrollDetail(with event: NSEvent) {
        surface?.scrollDetail(with: event)
    }

    func update(detailRect: CGRect?, centerY: CGFloat?) {
        guard self.detailRect != detailRect || detailCenterY != centerY else { return }
        self.detailRect = detailRect
        detailCenterY = centerY
        geometryDidChange?()
    }
}
