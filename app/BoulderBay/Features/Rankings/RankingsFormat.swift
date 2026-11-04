import Foundation

/// The wording shared by the Rankings screen and the map's best-pick button.
enum RankingsFormat {
    /// "Best right now", or "Best at 7 PM" for another hour.
    static func bestButton(hour: Int, isNow: Bool) -> String {
        "Best \(when(hour: hour, isNow: isNow))"
    }

    /// What the map's button says when there is no rank 1 to fly to.
    static func nothingOpen(near place: String, hour: Int, isNow: Bool) -> String {
        "Nothing open near \(place) \(when(hour: hour, isNow: isNow))"
    }

    /// "right now", or "at 7 PM" for another hour.
    static func when(hour: Int, isNow: Bool) -> String {
        isNow ? "right now" : "at \(GymDetailFormat.clock(hour: hour, minute: 0))"
    }
}

// MARK: - The Rankings screen

extension RankingsFormat {
    /// "Live, 5 PM", or "Forecast for 7 PM" for another hour.
    static func timeLabel(hour: Int, isNow: Bool) -> String {
        let clock = GymDetailFormat.clock(hour: hour, minute: 0)
        return isNow ? "Live, \(clock)" : "Forecast for \(clock)"
    }

    /// "Now", or "7 PM" for another hour.
    static func timeChip(hour: Int, isNow: Bool) -> String {
        isNow ? "Now" : GymDetailFormat.clock(hour: hour, minute: 0)
    }

    /// "Best pick right now", or "Best pick for 7 PM" for another hour.
    static func bestPickTitle(hour: Int, isNow: Bool) -> String {
        isNow ? "Best pick right now" : "Best pick for \(GymDetailFormat.clock(hour: hour, minute: 0))"
    }

    /// A drive up to this long reads as "close".
    static let closeMinutes = 20.0

    /// Why this gym won, saying only what's true of it. The mockup's rule always calls the gym
    /// close and names its crowd, but rank 1 can be a long drive away, or packed like everywhere
    /// else: then that part is left out, and the card's bottom row still gives both numbers.
    static func why(rankedGym: RankedGym, isMember: Bool, place: String, hour: Int, isNow: Bool) -> String {
        let when = when(hour: hour, isNow: isNow)
        let crowd = crowdPhrase(rankedGym.gym.busyness)
        let isClose = rankedGym.travelMinutes <= closeMinutes
        let bestOfWhatsOpen = "the best of what's open \(when)"

        if isMember {
            guard let crowd else { return "Your gym, and \(bestOfWhatsOpen)" }
            return "Your gym, and it\(isNow ? "'s" : " should be") \(crowd) \(when)"
        }
        switch (crowd, isClose) {
        case (let crowd?, true): return "\(crowd.capitalizedFirst) \(when) and close to \(place)"
        case (let crowd?, false): return "\(crowd.capitalizedFirst) \(when)"
        case (nil, true): return "Close to \(place)"
        case (nil, false): return bestOfWhatsOpen.capitalizedFirst
        }
    }

    /// How the crowd reads inside a sentence, or nil when it's no reason to go.
    private static func crowdPhrase(_ busyness: ResolvedBusyness) -> String? {
        switch busyness.level {
        case .quiet: "quiet"
        case .moderate: "moderately busy"
        case .packed: nil
        case nil: "open"
        }
    }

    /// "Quiet", or "Open" for an open gym with no reading, which is never shown as 0%.
    static func busynessWord(_ busyness: ResolvedBusyness) -> String {
        busyness.level?.rawValue.capitalized ?? "Open"
    }

    /// "18 min away". Never "0 min", for a gym next door.
    static func travel(minutes: Double) -> String {
        "\(max(1, Int(minutes.rounded()))) min away"
    }

    /// For an empty list. The answer doesn't say whether gyms are closed or just too far.
    static func emptyTitle(near place: String, hour: Int, isNow: Bool) -> String {
        "No gym near \(place) is open \(when(hour: hour, isNow: isNow))"
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
