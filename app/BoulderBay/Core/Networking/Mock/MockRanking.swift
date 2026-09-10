import Foundation

/// The prototype ranking formula from `boulder_bay_plan.md`, in the mock so rankings
/// come back the way the backend will compute them. Travel time uses the plan's Mapbox
/// fallback (`6 + miles × 2.3`) since there is no Matrix API here.
enum MockRanking {
    struct Weights: Sendable {
        var crowd = 0.6
        var travel = 0.5
        var memberBoost = 15.0
        var closedPenalty = 60.0
        var travelCapMinutes = 60
        static let defaults = Weights()
    }

    /// Great-circle distance in statute miles.
    static func miles(
        fromLatitude lat1: Double, longitude lng1: Double,
        toLatitude lat2: Double, longitude lng2: Double
    ) -> Double {
        let radius = 3958.8
        let toRadians = Double.pi / 180
        let dLat = (lat2 - lat1) * toRadians
        let dLng = (lng2 - lng1) * toRadians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRadians) * cos(lat2 * toRadians) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * radius * asin(sqrt(a))
    }

    static func travelMinutes(miles: Double) -> Int {
        Int((6 + miles * 2.3).rounded())
    }

    /// `100 − w_crowd·busy − w_travel·min(travel, cap) + boost·member − penalty·closed`.
    /// A closed gym has no busyness, which counts as 0 — the penalty carries the weight.
    static func score(
        busyPct: Int?, travelMinutes: Int, isMember: Bool, isOpen: Bool,
        weights: Weights = .defaults
    ) -> Double {
        var score = 100.0
        score -= weights.crowd * Double(busyPct ?? 0)
        score -= weights.travel * Double(min(travelMinutes, weights.travelCapMinutes))
        if isMember { score += weights.memberBoost }
        if !isOpen { score -= weights.closedPenalty }
        return (score * 10).rounded() / 10
    }
}
