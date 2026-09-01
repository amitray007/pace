import Foundation
import SwiftUI

struct PaceNotificationSettingsContent: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        Section("Notifications") {
            Toggle(
                "Usage threshold alerts",
                isOn: Binding(
                    get: { model.usageNotificationsEnabled },
                    set: model.setUsageNotificationsEnabled,
                ),
            )

            if model.usageNotificationsEnabled {
                HStack(spacing: 10) {
                    Text("Alert at")
                    Spacer()
                    Slider(
                        value: Binding(
                            get: { model.notificationUsageThreshold },
                            set: model.setNotificationUsageThreshold,
                        ),
                        in: 0.5 ... 0.95,
                        step: 0.05,
                    )
                    .frame(width: 170)
                    .accessibilityLabel("Usage alert threshold")
                    .accessibilityValue(
                        Text(
                            model.notificationUsageThreshold,
                            format: .percent.precision(.fractionLength(0)),
                        ),
                    )
                    Text(
                        model.notificationUsageThreshold,
                        format: .percent.precision(.fractionLength(0)),
                    )
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
                }
            }

            Toggle(
                "Reset reminders",
                isOn: Binding(
                    get: { model.resetNotificationsEnabled },
                    set: model.setResetNotificationsEnabled,
                ),
            )

            if model.resetNotificationsEnabled {
                Picker(
                    "Remind before reset",
                    selection: Binding(
                        get: { model.notificationResetLeadTime },
                        set: model.setNotificationResetLeadTime,
                    ),
                ) {
                    Text("15 minutes").tag(TimeInterval(15 * 60))
                    Text("30 minutes").tag(TimeInterval(30 * 60))
                    Text("1 hour").tag(TimeInterval(60 * 60))
                    Text("2 hours").tag(TimeInterval(2 * 60 * 60))
                    Text("4 hours").tag(TimeInterval(4 * 60 * 60))
                }
            }

            Toggle(
                "Warn when data becomes stale",
                isOn: Binding(
                    get: { model.staleDataNotificationsEnabled },
                    set: model.setStaleDataNotificationsEnabled,
                ),
            )

            Toggle(
                "Quiet hours",
                isOn: Binding(
                    get: { model.quietHoursEnabled },
                    set: model.setQuietHoursEnabled,
                ),
            )

            if model.quietHoursEnabled {
                DatePicker(
                    "Quiet from",
                    selection: Binding(
                        get: { model.quietHoursStartDate },
                        set: model.setQuietHoursStartDate,
                    ),
                    displayedComponents: .hourAndMinute,
                )
                DatePicker(
                    "Quiet until",
                    selection: Binding(
                        get: { model.quietHoursEndDate },
                        set: model.setQuietHoursEndDate,
                    ),
                    displayedComponents: .hourAndMinute,
                )
            }

            authorizationStatus

            if let notificationError = model.notificationError {
                Label(notificationError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var authorizationStatus: some View {
        if !model.notificationPolicy.isEnabled {
            Text("Alerts are off. Pace asks for permission only after you enable one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            switch model.notificationAuthorizationStatus {
            case .authorized:
                Label("Notifications are allowed on this Mac.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .denied:
                Label(
                    "Notifications are blocked in System Settings.",
                    systemImage: "exclamationmark.triangle",
                )
                .foregroundStyle(.orange)
            case .ephemeral, .provisional:
                Label("Notifications will be delivered quietly.", systemImage: "moon")
                    .foregroundStyle(.secondary)
            case .notDetermined:
                HStack(spacing: 8) {
                    Text(
                        model.isChangingNotificationAuthorization
                            ? "Waiting for macOS notification permission."
                            : "macOS permission has not been requested.",
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow Notifications") {
                        model.requestNotificationAuthorization()
                    }
                    .disabled(model.isChangingNotificationAuthorization)
                }
            case .unavailable:
                Label(
                    "Notifications are unavailable in this build.",
                    systemImage: "exclamationmark.triangle",
                )
                .foregroundStyle(.orange)
            }
        }
    }
}
