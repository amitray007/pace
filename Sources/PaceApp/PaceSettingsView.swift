import SwiftUI

struct PaceSettingsView: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        Form {
            Section("Surfaces") {
                Toggle("Show edge rail", isOn: $model.isRailVisible)
                Picker("Static reference state", selection: $model.railPreviewState) {
                    Text("Mini handle").tag(RailPreviewState.mini)
                    Text("Rail").tag(RailPreviewState.rail)
                    Text("Claude detail").tag(RailPreviewState.claude)
                    Text("Codex detail").tag(RailPreviewState.codex)
                    Text("Cursor detail").tag(RailPreviewState.cursor)
                }
            }

            Section("Data") {
                LabeledContent("Source", value: "Deterministic simulation")
                Text(
                    "Live adapters stay disconnected until visual and interaction approval.",
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 280)
    }
}
