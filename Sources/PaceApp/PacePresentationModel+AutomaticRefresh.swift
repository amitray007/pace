import Foundation

/// The app-level refresh sweep.
///
/// Adapters poll their own providers, but nothing refreshed every account
/// on a schedule, so a panel left open drifted out of date the longer it
/// stayed open.
extension PacePresentationModel {
    /// Runs an automatic refresh on a repeating schedule.
    ///
    /// Without this, usage only updated at launch or when the user pressed
    /// refresh, so a panel left open drifted further out of date the longer it
    /// stayed open.
    func startAutomaticRefresh() {
        guard automaticRefreshTask == nil, !isReferencePreview else {
            return
        }
        scheduleNextRefresh()
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(Self.automaticRefreshInterval),
                )
                guard !Task.isCancelled else {
                    return
                }
                await self?.refreshAll()
            }
        }
    }

    func stopAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        clearNextRefresh()
    }
}
