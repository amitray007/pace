import PaceCore
import SwiftUI

struct ManagedProviderAccountRow: View {
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
            // The name field is never disabled by the model's busy flags.
            // Disabling it while it is being edited forces AppKit to end the
            // editing session: the field loses focus, the blur commit fires a
            // second rename that the busy guard rejects, and the field then
            // refuses to take focus again until Settings is reopened. A rename
            // only touches the store, so it does not need that exclusivity.
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
            .disabled(isManagingAccounts)
            .accessibilityLabel("Enable \(account.displayName)")

            if model.needsKeychainAuthorization(account) {
                KeychainAccessButton(model: model, account: account)
            }

            Button(role: .destructive) {
                confirmsRemoval = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isManagingAccounts)
            .accessibilityLabel("Remove \(account.displayName)")
        }
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
                Task { await model.removeManagedAccount(account.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Pace will remove its saved usage for this account. "
                    + "The provider profile and credentials stay unchanged.",
            )
        }
    }

    private var isManagingAccounts: Bool {
        model.isProviderRuntimeBusy || model.isManagingAccounts || model.isRefreshing
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
