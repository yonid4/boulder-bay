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
