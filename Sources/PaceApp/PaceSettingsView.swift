import Foundation
import PaceCore
import SwiftUI
import UniformTypeIdentifiers

struct PaceSettingsView: View {
    @Bindable var model: PacePresentationModel
    @State private var isChoosingCodexProfile = false
    @State private var isChoosingGrokProfile = false
    @State private var isChoosingGitHubCopilotAccount = false

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

                if !model.isReferencePreview {
                    ForEach(model.managedAccounts(for: .codex)) { account in
                        ManagedProviderAccountRow(model: model, account: account)
                    }

                    HStack(spacing: 8) {
                        Button("Add current Codex account") {
                            Task {
                                await model.addDefaultCodexAccount()
                            }
                        }
                        Button("Choose profile folder...") {
                            isChoosingCodexProfile = true
                        }
                    }
                    .disabled(model.isLoading || model.isManagingAccounts || model.isRefreshing)

                    Text(
                        "For another Codex account, sign in with a separate CODEX_HOME, "
                            + "then choose that folder.",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    ForEach(model.managedAccounts(for: .grok)) { account in
                        ManagedProviderAccountRow(model: model, account: account)
                    }

                    HStack(spacing: 8) {
                        Button("Add current Grok account") {
                            Task {
                                await model.addDefaultGrokAccount()
                            }
                        }
                        Button("Choose Grok profile folder...") {
                            isChoosingGrokProfile = true
                        }
                    }
                    .disabled(model.isLoading || model.isManagingAccounts || model.isRefreshing)

                    Text(
                        "For another Grok account, sign in with a separate GROK_HOME, "
                            + "then choose that folder.",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    ForEach(model.managedAccounts(for: .githubCopilot)) { account in
                        ManagedProviderAccountRow(model: model, account: account)
                    }

                    Button("Add GitHub Copilot account...") {
                        Task {
                            if await model.prepareGitHubCopilotAccountSelection() {
                                isChoosingGitHubCopilotAccount = true
                            }
                        }
                    }
                    .disabled(model.isLoading || model.isManagingAccounts || model.isRefreshing)

                    Text(
                        "Pace reads only the GitHub CLI account you select. "
                            + "Add more accounts with gh auth login.",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    if let accountActionError = model.accountActionError {
                        Label(accountActionError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Activation") {
                Picker(
                    "Open rail",
                    selection: Binding(
                        get: { model.preferences.activationMode },
                        set: model.setActivationMode,
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
                            set: model.setActivationModifier,
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
                            set: model.setDwellDelay,
                        ),
                        range: 0.2 ... 2,
                    )
                }

                delayControl(
                    "Dismissal grace",
                    value: Binding(
                        get: { model.preferences.dismissalDelay },
                        set: model.setDismissalDelay,
                    ),
                    range: 0.1 ... 2,
                )

                Toggle(
                    "Hide in full-screen apps",
                    isOn: Binding(
                        get: { model.preferences.hideRailInFullScreen },
                        set: model.setHideRailInFullScreen,
                    ),
                )
            }

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
        .formStyle(.grouped)
        .frame(width: 500, height: 590)
        .task {
            await model.start()
        }
        .fileImporter(
            isPresented: $isChoosingCodexProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { result in
            switch result {
            case let .success(urls):
                guard let directory = urls.first else {
                    return
                }
                Task {
                    await model.addCodexProfile(at: directory)
                }
            case let .failure(error):
                if (error as? CocoaError)?.code != .userCancelled {
                    model.reportAccountPickerError(error, providerID: .codex)
                }
            }
        }
        .fileImporter(
            isPresented: $isChoosingGrokProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { result in
            switch result {
            case let .success(urls):
                guard let directory = urls.first else {
                    return
                }
                Task {
                    await model.addGrokProfile(at: directory)
                }
            case let .failure(error):
                if (error as? CocoaError)?.code != .userCancelled {
                    model.reportAccountPickerError(error, providerID: .grok)
                }
            }
        }
        .confirmationDialog(
            "Add GitHub Copilot account",
            isPresented: $isChoosingGitHubCopilotAccount,
            titleVisibility: .visible,
        ) {
            ForEach(model.availableGitHubCopilotLogins, id: \.self) { login in
                Button(login) {
                    Task {
                        await model.addGitHubCopilotAccount(githubLogin: login)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose one authenticated GitHub CLI account.")
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

private struct ManagedProviderAccountRow: View {
    @Bindable var model: PacePresentationModel
    let account: ProviderAccount
    @FocusState private var nameIsFocused: Bool
    @State private var draftName: String
    @State private var confirmsRemoval = false

    init(model: PacePresentationModel, account: ProviderAccount) {
        self.model = model
        self.account = account
        _draftName = State(initialValue: account.displayName)
    }

    var body: some View {
        HStack(spacing: 8) {
            ProviderMark(
                providerID: account.providerID,
                color: ProviderStyle.resolve(account.providerID).accent,
                size: 11,
            )
            TextField("Account name", text: $draftName)
                .focused($nameIsFocused)
                .onSubmit(commitName)
                .onChange(of: nameIsFocused) { wasFocused, isFocused in
                    if wasFocused, !isFocused {
                        commitName()
                    }
                }

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { account.isEnabled },
                    set: { isEnabled in
                        Task {
                            await model.setManagedAccount(account.id, isEnabled: isEnabled)
                        }
                    },
                ),
            )
            .labelsHidden()
            .accessibilityLabel("Enable \(account.displayName)")

            Button(role: .destructive) {
                confirmsRemoval = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(account.displayName)")
        }
        .disabled(model.isLoading || model.isManagingAccounts || model.isRefreshing)
        .onChange(of: account.displayName) { _, displayName in
            if !nameIsFocused {
                draftName = displayName
            }
        }
        .confirmationDialog(
            "Remove \(account.displayName)?",
            isPresented: $confirmsRemoval,
        ) {
            Button("Remove Account", role: .destructive) {
                Task {
                    await model.removeManagedAccount(account.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Pace will remove its saved usage for this account. "
                    + "The provider profile and credentials stay unchanged.",
            )
        }
    }

    private func commitName() {
        let submittedName = draftName
        guard submittedName != account.displayName else {
            return
        }
        Task {
            let didRename = await model.renameManagedAccount(account.id, to: submittedName)
            if !didRename {
                draftName = account.displayName
            }
        }
    }
}
