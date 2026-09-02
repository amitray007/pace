import Foundation
import PaceCore
import SwiftUI
import UniformTypeIdentifiers

struct ProviderAccountsSettingsContent: View {
    @Bindable var model: PacePresentationModel
    @State private var isChoosingClaudeProfile = false
    @State private var isChoosingCodexProfile = false
    @State private var isChoosingCursorProfile = false
    @State private var isChoosingGrokProfile = false
    @State private var isChoosingGitHubCopilotAccount = false

    var body: some View {
        Group {
            accountRows(for: .claude)

            HStack(spacing: 8) {
                Button("Add current Claude account") {
                    Task { await model.addDefaultClaudeAccount() }
                }
                Button("Choose Claude profile folder...") {
                    isChoosingClaudeProfile = true
                }
            }
            .disabled(accountActionsAreDisabled)

            Text(
                "For another Claude account, sign in with a separate CLAUDE_CONFIG_DIR, "
                    + "then choose that folder. Add current also honors "
                    + "CLAUDE_SECURESTORAGE_CONFIG_DIR.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            accountRows(for: .codex)

            HStack(spacing: 8) {
                Button("Add current Codex account") {
                    Task { await model.addDefaultCodexAccount() }
                }
                Button("Choose profile folder...") {
                    isChoosingCodexProfile = true
                }
            }
            .disabled(accountActionsAreDisabled)

            Text(
                "For another Codex account, sign in with a separate CODEX_HOME, "
                    + "then choose that folder.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            accountRows(for: .cursor)

            HStack(spacing: 8) {
                Button("Add current Cursor account") {
                    Task { await model.addDefaultCursorAccount() }
                }
                Button("Choose Cursor profile home...") {
                    isChoosingCursorProfile = true
                }
            }
            .disabled(accountActionsAreDisabled)

            Text(
                "For another Cursor account, sign in with Cursor Agent from a separate home "
                    + "using AGENT_CLI_CREDENTIAL_STORE=file, then choose that home folder.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            accountRows(for: .grok)

            HStack(spacing: 8) {
                Button("Add current Grok account") {
                    Task { await model.addDefaultGrokAccount() }
                }
                Button("Choose Grok profile folder...") {
                    isChoosingGrokProfile = true
                }
            }
            .disabled(accountActionsAreDisabled)

            Text(
                "For another Grok account, sign in with a separate GROK_HOME, "
                    + "then choose that folder.",
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            accountRows(for: .githubCopilot)

            Button("Add GitHub Copilot account...") {
                Task {
                    if await model.prepareGitHubCopilotAccountSelection() {
                        isChoosingGitHubCopilotAccount = true
                    }
                }
            }
            .disabled(accountActionsAreDisabled)

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
        .fileImporter(
            isPresented: $isChoosingClaudeProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { handleProfileSelection($0, providerID: .claude) }
        .fileImporter(
            isPresented: $isChoosingCodexProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { handleProfileSelection($0, providerID: .codex) }
        .fileImporter(
            isPresented: $isChoosingCursorProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { handleProfileSelection($0, providerID: .cursor) }
        .fileImporter(
            isPresented: $isChoosingGrokProfile,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { handleProfileSelection($0, providerID: .grok) }
        .confirmationDialog(
            "Add GitHub Copilot account",
            isPresented: $isChoosingGitHubCopilotAccount,
            titleVisibility: .visible,
        ) {
            ForEach(model.availableGitHubCopilotLogins, id: \.self) { login in
                Button(login) {
                    Task { await model.addGitHubCopilotAccount(githubLogin: login) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose one authenticated GitHub CLI account.")
        }
    }

    private var accountActionsAreDisabled: Bool {
        model.isProviderRuntimeBusy || model.isManagingAccounts || model.isRefreshing
    }

    private func accountRows(for providerID: ProviderID) -> some View {
        ForEach(model.managedAccounts(for: providerID)) { account in
            ManagedProviderAccountRow(model: model, account: account)
        }
    }

    private func handleProfileSelection(
        _ result: Result<[URL], any Error>,
        providerID: ProviderID,
    ) {
        switch result {
        case let .success(urls):
            guard let directory = urls.first else {
                return
            }
            Task {
                switch providerID {
                case .claude:
                    await model.addClaudeProfile(at: directory)
                case .codex:
                    await model.addCodexProfile(at: directory)
                case .cursor:
                    await model.addCursorProfile(at: directory)
                case .grok:
                    await model.addGrokProfile(at: directory)
                default:
                    break
                }
            }
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                model.reportAccountPickerError(error, providerID: providerID)
            }
        }
    }
}
