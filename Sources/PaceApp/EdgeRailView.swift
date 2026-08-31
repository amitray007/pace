import AppKit
import PaceCore
import SwiftUI

enum EdgeRailGeometry {
    static let canvasSize = NSSize(width: 324, height: 416)
    static let railWidth: CGFloat = 70
    static let detailWidth: CGFloat = 226
    static let connectorWidth: CGFloat = 28
    static let railOriginX = detailWidth + connectorWidth
    static let railTopY: CGFloat = 30
    static let providerCentersY: [CGFloat] = [92, 194, 297]
    static let providerTopY: [CGFloat] = [60, 162, 265]
}

struct EdgeRailView: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        let providerIDs = Array(model.visibleProviderIDs.prefix(3))
        ZStack(alignment: .topLeading) {
            RailShellLayerRepresentable(
                previewState: model.railPreviewState,
                edge: model.preferences.railEdge,
                detailCenterY: detailCenterY(providerIDs: providerIDs),
            )

            if model.railPreviewState != .mini {
                providerRows(providerIDs: providerIDs)
                settingsMark
            }

            if let providerID = model.railPreviewState.detailProviderID {
                detailContent(providerID: providerID, providerIDs: providerIDs)
            }
        }
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pace edge usage rail")
    }

    private func providerRows(providerIDs: [ProviderID]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(providerIDs.enumerated()), id: \.element) { index, providerID in
                EdgeProviderRow(
                    providerID: providerID,
                    usage: model.headlineUsage(for: providerID) ?? 0,
                )
                .frame(width: EdgeRailGeometry.railWidth, height: 64)
                .offset(
                    x: railContentOriginX,
                    y: EdgeRailGeometry.providerTopY[index],
                )
            }
        }
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
            alignment: .topLeading,
        )
    }

    private var settingsMark: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 50, height: 50)
            .offset(x: settingsOriginX, y: 367)
            .accessibilityLabel("Pace settings")
    }

    private func detailContent(providerID: ProviderID, providerIDs: [ProviderID]) -> some View {
        let centerY = detailCenterY(providerIDs: providerIDs) ?? 92
        let panelY = min(max(centerY - 69.5, 0), 205)
        return EdgeDetailPanel(
            providerID: providerID,
            account: model.selectedAccount(for: providerID),
            snapshots: model.selectedAccount(for: providerID)
                .map { model.snapshots(for: $0.id) } ?? [],
        )
        .frame(width: EdgeRailGeometry.detailWidth, height: 139, alignment: .topLeading)
        .offset(x: detailOriginX, y: panelY)
    }

    private func detailCenterY(providerIDs: [ProviderID]) -> CGFloat? {
        guard let providerID = model.railPreviewState.detailProviderID,
              let index = providerIDs.firstIndex(of: providerID),
              EdgeRailGeometry.providerCentersY.indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY[index]
    }

    private var railContentOriginX: CGFloat {
        model.preferences.railEdge == .right ? EdgeRailGeometry.railOriginX : 0
    }

    private var detailOriginX: CGFloat {
        model.preferences.railEdge == .right
            ? 0
            : EdgeRailGeometry.canvasSize.width - EdgeRailGeometry.detailWidth
    }

    private var settingsOriginX: CGFloat {
        model.preferences.railEdge == .right ? EdgeRailGeometry.railOriginX + 10 : 10
    }
}

private struct EdgeProviderRow: View {
    let providerID: ProviderID
    let usage: Double

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        VStack(spacing: 8) {
            ZStack {
                ProgressRingLayerRepresentable(
                    fraction: usage,
                    color: style.accentColor,
                )
                .frame(width: 40, height: 40)

                ProviderMark(providerID: providerID, color: .white, size: 13)
            }
            Text(usage, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(style.name), \(Int(usage * 100)) percent used",
        )
    }
}

private struct EdgeDetailPanel: View {
    let providerID: ProviderID
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ProviderMark(providerID: providerID, color: .white, size: 10)
                Text("\(style.name) Usage")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(account?.displayName ?? "No account")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshots.prefix(2)) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snapshot.label)
                        Spacer()
                        Text(snapshot.usedFraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.system(size: 8.5, weight: .medium))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(style.accent)
                                .frame(width: proxy.size.width * min(snapshot.usedFraction, 1))
                        }
                    }
                    .frame(height: 3)

                    Text(resetText(for: snapshot))
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            Divider()
                .overlay(Color.white.opacity(0.14))

            HStack(spacing: 8) {
                Text(account?.planName ?? "Plan unavailable")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(observationText)
                    .lineLimit(1)
            }
            .font(.system(size: 7.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(style.name) usage for \(account?.displayName ?? "no account")")
    }

    private func resetText(for snapshot: LimitSnapshot) -> String {
        guard let resetsAt = snapshot.resetsAt else {
            return "Reset unavailable"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relativeReset = formatter.localizedString(
            for: resetsAt,
            relativeTo: SimulatedScenarios.referenceDate,
        )
        return "Resets \(relativeReset)"
    }

    private var observationText: String {
        guard let latestObservation = snapshots.map(\.observedAt).max() else {
            return "Not observed"
        }
        let prefix = snapshots.allSatisfy { $0.freshness == .current } ? "Observed" : "Stale"
        return "\(prefix) \(latestObservation.formatted(date: .omitted, time: .shortened))"
    }
}

private struct RailShellLayerRepresentable: NSViewRepresentable {
    let previewState: RailPreviewState
    let edge: RailEdge
    let detailCenterY: CGFloat?

    func makeNSView(context _: Context) -> RailShellLayerView {
        RailShellLayerView()
    }

    func updateNSView(_ view: RailShellLayerView, context _: Context) {
        view.update(
            previewState: previewState,
            edge: edge,
            detailCenterY: detailCenterY,
        )
    }
}

private final class RailShellLayerView: NSView {
    private let detailLayer = CAShapeLayer()
    private let railLayer = CAShapeLayer()
    private let settingsLayer = CAShapeLayer()
    private var previewState: RailPreviewState = .rail
    private var edge: RailEdge = .right
    private var detailCenterY: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(detailLayer)
        layer?.addSublayer(railLayer)
        layer?.addSublayer(settingsLayer)
        for item in [detailLayer, railLayer, settingsLayer] {
            item.fillColor = NSColor.black.cgColor
            item.actions = ["path": NSNull(), "opacity": NSNull()]
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    func update(
        previewState: RailPreviewState,
        edge: RailEdge,
        detailCenterY: CGFloat?,
    ) {
        let changed = self.previewState != previewState || self.edge != edge ||
            self.detailCenterY != detailCenterY
        self.previewState = previewState
        self.edge = edge
        self.detailCenterY = detailCenterY
        if changed {
            updatePaths()
        }
    }

    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        railLayer.frame = bounds
        settingsLayer.frame = bounds
        detailLayer.frame = bounds

        if previewState == .mini {
            railLayer.path = transformed(miniPath())
            settingsLayer.opacity = 0
            detailLayer.opacity = 0
        } else {
            railLayer.path = transformed(railPath())
            settingsLayer.path = transformed(settingsPath())
            settingsLayer.opacity = 1
            updateDetailPath()
        }
        CATransaction.commit()
    }

    private func updateDetailPath() {
        guard previewState.detailProviderID != nil else {
            detailLayer.opacity = 0
            return
        }
        let centerY = detailCenterY ?? 92
        let panelY = min(max(centerY - 69.5, 0), 205)
        let panelRect = CGRect(x: 0, y: panelY, width: EdgeRailGeometry.detailWidth, height: 139)
        let path = CGMutablePath()
        path.addRoundedRect(in: panelRect, cornerWidth: 16, cornerHeight: 16)
        path.move(to: CGPoint(x: panelRect.maxX - 1, y: centerY - 17))
        path.addLine(to: CGPoint(x: EdgeRailGeometry.railOriginX + 2, y: centerY))
        path.addLine(to: CGPoint(x: panelRect.maxX - 1, y: centerY + 17))
        path.closeSubpath()
        detailLayer.path = transformed(path)
        detailLayer.opacity = 1
    }

    private func transformed(_ path: CGPath) -> CGPath {
        var verticalFlip = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: bounds.height,
        )
        let verticallyFlippedPath = path.copy(using: &verticalFlip) ?? path
        guard edge == .left else {
            return verticallyFlippedPath
        }
        var horizontalFlip = CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: bounds.width,
            ty: 0,
        )
        return verticallyFlippedPath.copy(using: &horizontalFlip) ?? verticallyFlippedPath
    }

    private func miniPath() -> CGPath {
        CGPath(
            roundedRect: CGRect(
                x: EdgeRailGeometry.canvasSize.width - 18,
                y: 173,
                width: 18,
                height: 70,
            ),
            cornerWidth: 9,
            cornerHeight: 9,
            transform: nil,
        )
    }

    private func railPath() -> CGPath {
        let path = CGMutablePath()
        let leftX = EdgeRailGeometry.railOriginX
        let rightX = EdgeRailGeometry.canvasSize.width
        let topY = EdgeRailGeometry.railTopY
        path.move(to: CGPoint(x: rightX, y: topY))
        path.addLine(to: CGPoint(x: leftX + 38, y: topY))
        path.addCurve(
            to: CGPoint(x: leftX, y: topY + 48),
            control1: CGPoint(x: leftX + 38, y: topY + 20),
            control2: CGPoint(x: leftX, y: topY + 20),
        )
        path.addLine(to: CGPoint(x: leftX, y: 322))
        path.addCurve(
            to: CGPoint(x: leftX + 36, y: 350),
            control1: CGPoint(x: leftX, y: 338),
            control2: CGPoint(x: leftX + 20, y: 348),
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: 368),
            control1: CGPoint(x: leftX + 58, y: 350),
            control2: CGPoint(x: rightX - 4, y: 356),
        )
        path.addLine(to: CGPoint(x: rightX, y: topY))
        path.closeSubpath()
        return path
    }

    private func settingsPath() -> CGPath {
        let path = CGMutablePath()
        let rightX = EdgeRailGeometry.canvasSize.width
        path.move(to: CGPoint(x: rightX, y: 348))
        path.addCurve(
            to: CGPoint(x: rightX - 27, y: 370),
            control1: CGPoint(x: rightX - 2, y: 359),
            control2: CGPoint(x: rightX - 14, y: 366),
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: 416),
            control1: CGPoint(x: rightX - 3, y: 386),
            control2: CGPoint(x: rightX - 2, y: 404),
        )
        path.addLine(to: CGPoint(x: rightX, y: 348))
        path.closeSubpath()
        path.addEllipse(
            in: CGRect(x: EdgeRailGeometry.railOriginX + 12, y: 370, width: 46, height: 46),
        )
        return path
    }
}
