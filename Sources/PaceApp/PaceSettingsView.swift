import Foundation
import PaceCore
import SwiftUI

/// The settings surface.
///
/// Every `Binding` setter here is written as an explicit closure rather than
/// as a reference to the model's method. The app builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, so passing a method directly
/// makes the compiler emit an isolation-carrying reabstraction thunk, and
/// generating IR for those thunks crashes Swift 6.2 and 6.3 while compiling
/// this file. Calling the method inside a closure avoids the conversion.
struct PaceSettingsView: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        Form {
            surfacesSection
            menuBarSection
            providersSection
            activationSection
            dataSection
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 590)
        .task {
            await model.start()
        }
    }

    /// Each section is its own property. As one expression the Form was 235
    /// lines of nested generic view types, which overflowed the compiler's IR
    /// generator on CI ("SmallVector unable to grow"). Splitting it gives the
    /// compiler one section at a time.
    private var surfacesSection: some View {
        Section("Surfaces") {
            Toggle(
                "Hide account addresses",
                isOn: Binding(
                    get: { model.preferences.hidesAccountIdentity },
                    set: { model.setHidesAccountIdentity($0) },
                ),
            )
            .help(
                "Shows the provider name instead of the account address in "
                    + "every surface, for screenshots and screen sharing.",
            )

            Toggle(
                "Show edge rail",
                isOn: Binding(
                    get: { model.isRailVisible },
                    set: { model.setRailVisible($0) },
                ),
            )

            Picker(
                "Screen edge",
                selection: Binding(
                    get: { model.preferences.railEdge },
                    set: { model.setRailEdge($0) },
                ),
            ) {
                ForEach(RailEdge.allCases, id: \.self) { edge in
                    Text(edge.label).tag(edge)
                }
            }

            Picker(
                "Rail size",
                selection: Binding(
                    get: { model.preferences.railScale },
                    set: { model.setRailScale($0) },
                ),
            ) {
                ForEach(RailScale.allCases, id: \.self) { scale in
                    Text(scale.label).tag(scale)
                }
            }

            Picker(
                "Display",
                selection: Binding(
                    get: { model.preferences.selectedDisplayID },
                    set: { model.setSelectedDisplayID($0) },
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
                    set: { model.setRailVerticalPosition($0) },
                ),
            ) {
                ForEach(RailVerticalPosition.allCases, id: \.self) { position in
                    Text(position.label).tag(position)
                }
            }

            if !model.isReferencePreview {
                Toggle(
                    "Launch Pace at login",
                    isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { model.setLaunchAtLogin($0) },
                    ),
                )
                .disabled(
                    model.isChangingLaunchAtLogin
                        || model.launchAtLoginStatus == .unavailable,
                )

                if model.launchAtLoginStatus == .requiresApproval {
                    HStack(spacing: 8) {
                        Label(
                            "Approval is required in Login Items.",
                            systemImage: "exclamationmark.triangle",
                        )
                        .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") {
                            model.openLoginItemsSettings()
                        }
                    }
                } else if model.launchAtLoginStatus == .unavailable {
                    Text("Launch at login is unavailable in this build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let launchAtLoginError = model.launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var menuBarSection: some View {
        Section("Menu bar") {
            MenuBarSettingsContent(model: model)
        }
    }

    private var providersSection: some View {
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

            if !model.isReferencePreview {
                ProviderAccountsSettingsContent(model: model)
            }
        }
    }

    @ViewBuilder
    private var activationSection: some View {
        Section("Activation") {
            Picker(
                "Open rail",
                selection: Binding(
                    get: { model.preferences.activationMode },
                    set: { model.setActivationMode($0) },
                ),
            ) {
                ForEach(RailActivationMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if model.preferences.activationMode == .modifierHover {
                Picker(
                    "Modifier key",
                    selection: Binding(
                        get: { model.preferences.activationModifier },
                        // Written as a closure rather than passing the
                        // method directly: the reabstraction thunk Swift
                        // 6.2 generates for that conversion crashes its
                        // own IR generator (SmallVector overflow) when
                        // building this file.
                        set: { model.setActivationModifier($0) },
                    ),
                ) {
                    ForEach(RailActivationModifier.allCases, id: \.self) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
            }

            if model.preferences.activationMode == .dwellHover {
                delayControl(
                    "Hover delay",
                    value: Binding(
                        get: { model.preferences.dwellDelay },
                        set: { model.setDwellDelay($0) },
                    ),
                    range: 0.2 ... 2,
                )
            }

            delayControl(
                "Dismissal grace",
                value: Binding(
                    get: { model.preferences.dismissalDelay },
                    set: { model.setDismissalDelay($0) },
                ),
                range: 0.1 ... 2,
            )

            Toggle(
                "Hide in full-screen apps",
                isOn: Binding(
                    get: { model.preferences.hideRailInFullScreen },
                    set: { model.setHideRailInFullScreen($0) },
                ),
            )
        }

        if !model.isReferencePreview {
            PaceNotificationSettingsContent(model: model)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Source", value: model.dataSourceDescription)
            Text(
                model.isReferencePreview
                    ? "Reference review uses deterministic simulation."
                    :
                    "Pace stores normalized usage and profile references, "
                    + "not provider credentials.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if let preferencesError = model.preferencesError {
                Label(preferencesError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func delayControl(
        _ label: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
            Spacer()
            Slider(value: value, in: range, step: 0.1)
                .frame(width: 170)
                .accessibilityLabel(label)
                .accessibilityValue(
                    Text("\(value.wrappedValue, specifier: "%.1f") seconds"),
                )
            Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
            Text("s")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}
