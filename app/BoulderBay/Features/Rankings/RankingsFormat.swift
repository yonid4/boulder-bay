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

    /// The mockup's rule for why this gym won: it's yours, or it's quiet and close.
    static func why(gym: Gym, isMember: Bool, place: String, hour: Int, isNow: Bool) -> String {
        let word = busynessWord(gym.busyness)
        let when = when(hour: hour, isNow: isNow)
        if isMember {
            return "Your gym, and it\(isNow ? "'s" : " should be") \(word.lowercased()) \(when)"
        }
        return "\(word) \(when) and close to \(place)"
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
