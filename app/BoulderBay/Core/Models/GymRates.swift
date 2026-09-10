/// Day and monthly rates, in integer cents. Touchstone tiers its day rate by time of
/// day — `dayPassPeakCents` applies from `peakStartsAt` — and the database guarantees
/// those two are either both present or both absent.
struct GymRates: Codable, Hashable, Sendable {
    let dayPassCents: Int?
    let dayPassPeakCents: Int?
    let peakStartsAt: ClockTime?
    let monthlyCents: Int?

    enum CodingKeys: String, CodingKey {
        case dayPassCents = "day_pass_cents"
        case dayPassPeakCents = "day_pass_peak_cents"
        case peakStartsAt = "peak_starts_at"
        case monthlyCents = "monthly_cents"
    }

    var hasPeakTier: Bool { dayPassPeakCents != nil && peakStartsAt != nil }
}
