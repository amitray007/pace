import AppKit
import PaceCore
import SwiftUI

struct MenuPanelView: View {
    @Bindable var model: PacePresentationModel
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var focusedProviderID: ProviderID?
    @State private var showsAllAccounts = false

    var body: some View {
        VStack(spacing: 0) {
            providerTabs
            Divider().overlay(Color.white.opacity(dividerOpacity))

            if let loadingError = model.loadingError {
                ContentUnavailableView(
                    "Usage unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadingError),
                )
                .frame(minHeight: 120)
            } else if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if model.selectedAccount == nil {
                // Only claim there is no account once the first refresh has
                // finished. Before that an empty list means the providers have
                // not been read yet, and saying "No account configured" told
                // the user to go add one they already have.
                if model.isPerformingFirstRefresh {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ContentUnavailableView(
                        "No account configured",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Add an account for this provider to see usage."),
                    )
                    .frame(minHeight: 120)
                }
            } else if showsAllAccounts {
                allAccountsContent
            } else {
                selectedAccountContent
            }

            refreshSchedule
            Divider().overlay(Color.white.opacity(dividerOpacity))
            footer
        }
        // Width is fixed; height follows the content. The hosting controller
        // sizes the popover to its preferred content size, so a hand-computed
        // height only ever disagreed with what the views actually laid out, and
        // the surplus showed up as a gap above the footer.
        .frame(width: 326)
        .background(Color(red: 0.035, green: 0.035, blue: 0.04))
        .preferredColorScheme(.dark)
        .task {
            await model.start()
        }
    }

    private var providerTabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.visibleProviderIDs.enumerated()), id: \.element) { item in
                let (index, providerID) = item
                let style = ProviderStyle.resolve(providerID)
                Button {
                    showsAllAccounts = false
                    model.selectProvider(providerID)
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            ProviderMark(
                                providerID: providerID,
                                color: model.activeProviderID == providerID
                                    ? style.accent
                                    : Color.secondary,
                                size: 11,
                            )
                            Text(style.name)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)

                        Rectangle()
                            .fill(
                                model.activeProviderID == providerID
                                    ? style.accent
                                    : Color.clear,
                            )
                            .frame(height: usesIncreasedContrast ? 3 : 2)
                    }
                    .foregroundStyle(
                        model.activeProviderID == providerID ? style.accent : Color.secondary,
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedProviderID, equals: providerID)
                .keyboardShortcut(providerShortcut(index), modifiers: .command)
                .accessibilityLabel("Show \(style.name) usage")
                .accessibilityHint("Keyboard shortcut Command \(index + 1)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .onMoveCommand(perform: moveProviderFocus)
    }

    private var selectedAccountContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            accountHeader

            if model.selectedSnapshots.isEmpty {
                MenuUsageStateView(presentation: selectedStatusPresentation)
            } else {
                VStack(spacing: 14) {
                    ForEach(model.selectedSnapshots) { snapshot in
                        MenuQuotaRow(
                            snapshot: snapshot,
                            referenceDate: model.presentationReferenceDate,
                            accent: ProviderStyle.resolve(model.activeProviderID).accent,
                            increasedContrast: usesIncreasedContrast,
                        )
                    }
                }
            }
        }
        .padding(16)
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProviderMark(
                    providerID: model.activeProviderID,
                    color: ProviderStyle.resolve(model.activeProviderID).accent,
                    size: 14,
                )
                Text(ProviderStyle.resolve(model.activeProviderID).name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.accounts(for: model.activeProviderID).count > 1 {
                    Button("All accounts") {
                        showsAllAccounts = true
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(accountDetail)
                    .lineLimit(1)
                Spacer(minLength: 4)
                UsageStatusLabel(presentation: selectedStatusPresentation)
            }
            .font(.system(size: 9.5, weight: .medium))

            // Only a problem is stated here. When the data is healthy its
            // observation time sits beside the refresh countdown instead, so
            // the two time facts read together rather than bracketing the
            // quotas.
            if let detail = selectedStatusDetail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if let account = model.selectedAccountAwaitingKeychain {
                KeychainAccessButton(model: model, account: account)
                    .font(.system(size: 10, weight: .medium))
            }

            accountPicker
        }
    }

    @ViewBuilder
    private var accountPicker: some View {
        let accounts = model.accounts(for: model.activeProviderID)
        if accounts.count > 1, let selectedAccount = model.selectedAccount {
            Picker(
                "Account",
                selection: Binding(
                    get: { selectedAccount.id },
                    set: { accountID in
                        Task {
                            await model.selectAccount(accountID, for: model.activeProviderID)
                        }
                    },
                ),
            ) {
                ForEach(accounts) { account in
                    Text(model.displayName(for: account)).tag(account.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(
                "\(ProviderStyle.resolve(model.activeProviderID).name) account",
            )
            .accessibilityHint("Option Left Arrow or Option Right Arrow switches accounts")
        }
    }

    private var allAccountsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    showsAllAccounts = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("All \(ProviderStyle.resolve(model.activeProviderID).name) accounts")
                    .font(.system(size: 12, weight: .semibold))
            }

            ForEach(model.accounts(for: model.activeProviderID)) { account in
                AllAccountsRow(
                    account: account,
                    snapshots: model.snapshots(for: account.id),
                    status: model.usageStatus(for: account),
                    accent: ProviderStyle.resolve(model.activeProviderID).accent,
                    increasedContrast: usesIncreasedContrast,
                    displayName: model.displayName(for: account),
                )
            }
        }
        .padding(16)
    }

    /// When the next automatic refresh lands, stated just above the refresh
    /// control.
    ///
    /// This sits with the refresh button rather than in the account header. The
    /// header answers "whose usage is this"; the countdown answers "when does
    /// this change", which is the same question the refresh button answers, so
    /// the two belong together. It also keeps a moving number away from the
    /// identity line, where it drew the eye away from the reading.
    private var refreshSchedule: some View {
        HStack(spacing: 8) {
            RefreshCountdownView(
                nextRefreshAt: model.nextRefreshAt,
                isRefreshing: model.isRefreshing || model.isPerformingFirstRefresh,
                style: .sentence,
            )
            Spacer(minLength: 4)
            // When the data was last read, paired with when it will next be
            // read. Shown only when the data is healthy; otherwise the header
            // is already stating what is wrong with it.
            if selectedStatusDetail == nil, model.selectedAccount != nil {
                Text(selectedStatusPresentation.observationText)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        // The content above carries its own bottom padding, so this only needs
        // to clear the divider below.
        .padding(.bottom, 9)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await model.refreshAll()
                }
            } label: {
                Label(
                    model.isRefreshing ? "Refreshing" : "Refresh",
                    systemImage: "arrow.clockwise",
                )
            }
            .disabled(model.isProviderRuntimeBusy || model.isRefreshing || model.isManagingAccounts)
            .keyboardShortcut("r", modifiers: .command)

            Button {
                model.toggleRail()
            } label: {
                Label(
                    model.isRailVisible ? "Hide rail" : "Show rail",
                    systemImage: "sidebar.right",
                )
            }

            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Open Pace settings")

            // Pace has no Dock icon, so without this the panel offers no way
            // to quit and the only route is Activity Monitor.
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit Pace")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .topLeading) {
            if let refreshError = model.refreshError {
                Text(refreshError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .accessibilityLabel(refreshError)
                    .offset(x: 14, y: -17)
            }
        }
    }

    private var accountDetail: String {
        guard let account = model.selectedAccount else {
            return "No account"
        }
        return [model.displayName(for: account), account.planName]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var selectedStatusPresentation: UsageStatusPresentation {
        guard let status = model.selectedUsageStatus else {
            return .missing(isLoading: model.isPerformingFirstRefresh)
        }
        return UsageStatusPresentation.resolve(
            status,
            referenceDate: model.presentationReferenceDate,
        )
    }

    /// The problem with the current data, or nil when there is none.
    private var selectedStatusDetail: String? {
        selectedStatusPresentation.severity == .positive
            ? nil
            : selectedStatusPresentation.detail
    }
}

private extension MenuPanelView {
    var dividerOpacity: Double {
        usesIncreasedContrast ? 0.28 : 0.10
    }

    var usesIncreasedContrast: Bool {
        colorSchemeContrast == .increased || model.forcesIncreasedContrast
    }

    func providerShortcut(_ index: Int) -> KeyEquivalent {
        guard index < 9 else {
            return "0"
        }
        return KeyEquivalent(Character(String(index + 1)))
    }

    func moveProviderFocus(_ direction: MoveCommandDirection) {
        let providers = model.visibleProviderIDs
        guard let currentIndex = providers.firstIndex(of: model.activeProviderID) else {
            return
        }
        let nextIndex = switch direction {
        case .left:
            currentIndex - 1
        case .right:
            currentIndex + 1
        default:
            currentIndex
        }
        guard providers.indices.contains(nextIndex) else {
            return
        }
        let providerID = providers[nextIndex]
        showsAllAccounts = false
        model.selectProvider(providerID)
        focusedProviderID = providerID
    }
}
