import PaceCore

/// Spoken and hover description of the status item.
///
/// The drawn item is a mark and a bare number, neither of which names what it
/// measures. This says it in words, so the item is usable without sight and
/// explains itself on hover.
enum StatusItemAccessibility {
    static func description(for readings: [MenuBarReading]) -> String {
        guard !readings.isEmpty else {
            return "Pace usage limits"
        }
        return readings.map(phrase(for:)).joined(separator: ", ")
    }

    private static func phrase(for reading: MenuBarReading) -> String {
        let provider = ProviderStyle.resolve(reading.providerID).name
        let quota = reading.label.map { " \($0)" } ?? ""
        guard let usedFraction = reading.usedFraction else {
            return "\(provider)\(quota) unavailable"
        }
        let percentage = Int((min(max(usedFraction, 0), 1) * 100).rounded())
        return "\(provider)\(quota) \(percentage) percent used"
    }
}
