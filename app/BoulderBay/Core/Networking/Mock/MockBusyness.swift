import Foundation

/// Synthesizes the busyness the real backend scrapes. The shape is the mockup's: an
/// evening peak around 6:30 PM, a lunch bump, a small early-morning bump, scaled by a
/// per-gym factor and clipped to the gym's real hours. Deterministic on purpose, so
/// previews, tests and repeated launches all agree.
enum MockBusyness {
    /// Per-gym scale on the shared curve, so the sixteen don't all read the same.
    static let scale: [String: Double] = [
        "mission": 1.0, "dogpatch": 1.15, "hyperion": 0.9, "gwpc": 0.85, "pipe": 0.8,
        "ironworks": 0.9, "the-oaks": 0.75, "studio": 0.8,
        "mv-sf": 1.0, "mv-belmont": 0.95, "mv-mountain-view": 1.05, "mv-santa-clara": 1.1,
        "bm-sf": 1.05, "bm-berkeley": 0.9, "the-peak": 0.7, "mosaic": 0.65,
    ]

    /// Predicted busyness during `hour` for a gym with scale `k`, ignoring hours.
    static func typicalPct(hour: Int, scale k: Double) -> Int {
        let h = Double(hour)
        let raw = (gauss(h, 18.4, 2.1) * 90 + gauss(h, 12.2, 1.6) * 40 + gauss(h, 7.3, 1) * 32) * k + 7
        return Int(min(100, max(0, raw)).rounded())
    }

    /// One point per open hour — the `busyness_curves` rows the detail chart draws.
    static func forecast(slug: String, hours: HoursRange) -> [ForecastPoint] {
        let k = scale[slug] ?? 1
        return hours.openHours.map { ForecastPoint(hour: $0, busyPct: typicalPct(hour: $0, scale: k)) }
    }

    /// The "live" reading: the curve nudged by a small per-gym offset so live and
    /// typical disagree the way Google's do. Nil when the gym is closed at `hour`.
    static func livePct(slug: String, hour: Int, hours: HoursRange?) -> Int? {
        guard let hours, hours.contains(ClockTime(hour: hour)) else { return nil }
        let index = SeedData.gyms.firstIndex { $0.slug == slug } ?? 0
        let jitter = ((index * 37) % 9) - 4
        let typical = typicalPct(hour: hour, scale: scale[slug] ?? 1)
        return min(100, max(0, typical + jitter))
    }

    private static func gauss(_ x: Double, _ mean: Double, _ sigma: Double) -> Double {
        exp(-((x - mean) * (x - mean)) / (2 * sigma * sigma))
    }
}
