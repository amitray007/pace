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
