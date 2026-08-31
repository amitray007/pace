import PaceCore
import SwiftUI

struct PaceSettingsView: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        Form {
            Section("Surfaces") {
                Toggle(
                    "Show edge rail",
                    isOn: Binding(
                        get: { model.isRailVisible },
                        set: model.setRailVisible,
                    ),
                )

                Picker(
                    "Screen edge",
                    selection: Binding(
                        get: { model.preferences.railEdge },
                        set: model.setRailEdge,
                    ),
                ) {
                    ForEach(RailEdge.allCases, id: \.self) { edge in
                        Text(edge.label).tag(edge)
                    }
                }

                Picker(
                    "Display",
                    selection: Binding(
                        get: { model.preferences.selectedDisplayID },
                        set: model.setSelectedDisplayID,
                    ),
                ) {
                    Text("Main display").tag(String?.none)
                    ForEach(model.availableDisplays) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }

                Picker(
                    "Vertical position",
                    selection: Binding(
                        get: { model.preferences.railVerticalPosition },
                        set: model.setRailVerticalPosition,
                    ),
                ) {
                    ForEach(RailVerticalPosition.allCases, id: \.self) { position in
                        Text(position.label).tag(position)
                    }
                }
            }

            Section("Providers") {
                ForEach(Array(model.visibleProviderIDs.enumerated()), id: \.element) { item in
                    let (index, providerID) = item
                    let style = ProviderStyle.resolve(providerID)
                    HStack(spacing: 9) {
                        ProviderMark(providerID: providerID, color: style.accent, size: 12)
                        Text(style.name)
                        Spacer()
                        Button {
                            model.moveProvider(providerID, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == model.visibleProviderIDs.startIndex)
                        .accessibilityLabel("Move \(style.name) earlier")

                        Button {
                            model.moveProvider(providerID, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == model.visibleProviderIDs
                            .index(before: model.visibleProviderIDs.endIndex))
                        .accessibilityLabel("Move \(style.name) later")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Data") {
                LabeledContent("Source", value: "Deterministic simulation")
                Text(
                    "Live adapters stay disconnected until visual and interaction approval.",
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                if let preferencesError = model.preferencesError {
                    Label(preferencesError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 430)
        .task {
            await model.start()
        }
    }
}

private extension RailEdge {
    var label: String {
        switch self {
        case .left:
            "Left"
        case .right:
            "Right"
        }
    }
}

private extension RailVerticalPosition {
    var label: String {
        switch self {
        case .top:
            "Top"
        case .center:
            "Center"
        case .bottom:
            "Bottom"
        }
    }
}
