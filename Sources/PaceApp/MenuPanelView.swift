import PaceCore
import SwiftUI

struct MenuPanelView: View {
    @Bindable var model: PacePresentationModel
    @State private var showsAllAccounts = false

    var body: some View {
        VStack(spacing: 0) {
            providerTabs
            Divider().overlay(Color.white.opacity(0.10))

            if let loadingError = model.loadingError {
                ContentUnavailableView(
                    "Usage unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadingError),
                )
                .frame(maxHeight: .infinity)
            } else if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.selectedAccount == nil {
                ContentUnavailableView(
                    "No account configured",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Add an account for this provider to see usage."),
                )
                .frame(maxHeight: .infinity)
            } else if showsAllAccounts {
                allAccountsContent
            } else {
                selectedAccountContent
            }

            Divider().overlay(Color.white.opacity(0.10))
            footer
        }
        .frame(width: 326, height: panelHeight)
        .background(Color(red: 0.035, green: 0.035, blue: 0.04))
        .preferredColorScheme(.dark)
        .task {
            await model.start()
        }
    }

    private var providerTabs: some View {
        HStack(spacing: 0) {
            ForEach(model.visibleProviderIDs, id: \.self) { providerID in
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
                            .frame(height: 2)
                    }
                    .foregroundStyle(
                        model.activeProviderID == providerID ? style.accent : Color.secondary,
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(style.name) usage")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
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
                            referenceDate: SimulatedScenarios.referenceDate,
                            accent: ProviderStyle.resolve(model.activeProviderID).accent,
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProviderMark(
                    providerID: model.activeProviderID,
                    color: .white,
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

            Text(selectedStatusSubtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

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
                    Text(account.displayName).tag(account.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(
                "\(ProviderStyle.resolve(model.activeProviderID).name) account",
            )
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
                )
            }
            Spacer()
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                model.toggleRail()
            } label: {
                Label(
                    model.isRailVisible ? "Hide rail" : "Show rail",
                    systemImage: "sidebar.right",
                )
            }

            if model.isRailVisible {
                Button {
                    model.toggleRailDetails()
                } label: {
                    Label(
                        model.railPreviewState
                            .detailProviderID == nil ? "Show detail" : "Rail only",
                        systemImage: "rectangle.split.2x1",
                    )
                }
            }

            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Open Pace settings")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var accountDetail: String {
        guard let account = model.selectedAccount else {
            return "No account"
        }
        return [account.displayName, account.planName]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var selectedStatusPresentation: UsageStatusPresentation {
        guard let status = model.selectedUsageStatus else {
            return UsageStatusPresentation(
                title: "No account configured",
                detail: "Add an account for this provider to see usage.",
                symbolName: "person.crop.circle.badge.questionmark",
                severity: .neutral,
                observationText: "Not observed",
            )
        }
        return UsageStatusPresentation.resolve(status)
    }

    private var selectedStatusSubtitle: String {
        selectedStatusPresentation.severity == .positive
            ? selectedStatusPresentation.observationText
            : selectedStatusPresentation.detail
    }

    private var panelHeight: CGFloat {
        if showsAllAccounts {
            return 252
        }
        guard model.selectedAccount != nil else {
            return 220
        }

        let quotaCount = max(model.selectedSnapshots.count, 1)
        let rowsHeight = CGFloat(quotaCount * 44 + max(quotaCount - 1, 0) * 14)
        let accountPickerHeight: CGFloat = model.accounts(for: model.activeProviderID).count > 1
            ? 29
            : 0
        let stateHeight: CGFloat = model.selectedSnapshots.isEmpty ? 36 : 0
        return 178 + rowsHeight + accountPickerHeight + stateHeight
    }
}

private struct MenuQuotaRow: View {
    let snapshot: LimitSnapshot
    let referenceDate: Date
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.label)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(snapshot.usedFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.11))
                    Capsule()
                        .fill(accent)
                        .frame(width: proxy.size.width * min(snapshot.usedFraction, 1))
                }
            }
            .frame(height: 4)

            HStack {
                Text(resetDescription)
                Spacer()
                Text(observationDescription)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var resetDescription: String {
        guard let resetsAt = snapshot.resetsAt else {
            return "Reset unavailable"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Resets \(formatter.localizedString(for: resetsAt, relativeTo: referenceDate))"
    }

    private var accessibilityDescription: String {
        "\(snapshot.label), \(Int(snapshot.usedFraction * 100)) percent used, " +
            "\(resetDescription), \(observationDescription)"
    }

    private var observationDescription: String {
        let observation = snapshot.observedAt.formatted(date: .omitted, time: .shortened)
        switch snapshot.freshness {
        case .current:
            return "Observed \(observation)"
        case .aging:
            return "Aging · \(observation)"
        case .failed:
            return "Failed · \(observation)"
        case .signedOut:
            return "Signed out · \(observation)"
        case .stale:
            return "Stale · \(observation)"
        case .unavailable:
            return "Unavailable · \(observation)"
        }
    }
}

private struct MenuUsageStateView: View {
    let presentation: UsageStatusPresentation

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(presentation.color)
            Text(presentation.title)
                .font(.system(size: 12, weight: .semibold))
            Text(presentation.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title). \(presentation.detail)")
    }
}

private struct AllAccountsRow: View {
    let account: ProviderAccount
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus
    let accent: Color

    var body: some View {
        let urgent = snapshots.max { $0.usedFraction < $1.usedFraction }
        let presentation = UsageStatusPresentation.resolve(status)
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 30, height: 30)
                .overlay {
                    Text(account.displayName.prefix(1))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(account.planName ?? "Plan unavailable") · \(presentation.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(presentation.color)
            }
            Spacer()
            if let urgent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(urgent.usedFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(urgent.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(account.displayName), \(presentation.title). \(presentation.detail)",
        )
    }
}
