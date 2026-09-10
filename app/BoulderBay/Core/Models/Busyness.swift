/// Quiet / Moderate / Packed, derived on the client from a raw percentage. The API never
/// sends a level — thresholds are a presentation rule (`boulder_bay_plan.md`, "Busyness
/// thresholds"): `< 40` quiet, `< 70` moderate, otherwise packed.
enum BusynessLevel: String, Hashable, Sendable, CaseIterable {
    case quiet
    case moderate
    case packed

    init(percent: Int) {
        switch percent {
        case ..<40: self = .quiet
        case ..<70: self = .moderate
        default: self = .packed
        }
    }

    /// The word always leads; the number is secondary.
    var label: String {
        switch self {
        case .quiet: "Quiet"
        case .moderate: "Moderate"
        case .packed: "Packed"
        }
    }
}

/// One bar of a gym's forecast for today: the predicted busyness during `hour`.
struct ForecastPoint: Codable, Hashable, Sendable {
    let hour: Int
    let busyPct: Int

    enum CodingKeys: String, CodingKey {
        case hour
        case busyPct = "busy_pct"
    }

    var level: BusynessLevel { BusynessLevel(percent: busyPct) }
}

/// Pure helpers over a forecast. Kept UI-free so they can be unit-tested directly.
enum BusynessForecast {
    /// The recommended one-hour window: the future open hour with the lowest predicted
    /// busyness, ties going to the earlier hour. `nil` when no open hour remains after
    /// `hour` — the gym is closing soon or already closed.
    static func bestWindow(in forecast: [ForecastPoint], after hour: Int) -> ForecastPoint? {
        forecast
            .filter { $0.hour > hour }
            .min { lhs, rhs in
                lhs.busyPct != rhs.busyPct ? lhs.busyPct < rhs.busyPct : lhs.hour < rhs.hour
            }
    }

    /// The predicted busyness at `hour`, if the forecast covers it.
    static func busyPct(in forecast: [ForecastPoint], at hour: Int) -> Int? {
        forecast.first { $0.hour == hour }?.busyPct
    }
}
