import Foundation

/// A wall-clock time of day with no date or zone, as the API sends `gym_hours` and
/// `peak_starts_at`: `"HH:MM"` (also accepts `"HH:MM:SS"`, which pydantic emits).
/// Interpreted in the gym's own timezone by whoever formats it.
struct ClockTime: Hashable, Sendable, Comparable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    init?(_ string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        self.init(hour: parts[0], minute: parts[1])
    }

    /// Minutes since midnight — the natural key for ordering and "is it open" checks.
    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

extension ClockTime: Codable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let time = ClockTime(raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a HH:MM time: \(raw)")
            )
        }
        self = time
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d", hour, minute))
    }
}

/// An open-to-close span within one day. `gym_hours` rejects past-midnight closing,
/// so `closesAt` is always after `opensAt`.
struct HoursRange: Codable, Hashable, Sendable {
    let opensAt: ClockTime
    let closesAt: ClockTime

    enum CodingKeys: String, CodingKey {
        case opensAt = "opens_at"
        case closesAt = "closes_at"
    }

    /// Whether the span contains the given clock time (open-inclusive, close-exclusive).
    func contains(_ time: ClockTime) -> Bool {
        opensAt <= time && time < closesAt
    }

    /// The whole hours a gym is open, e.g. 6...21 for 06:00–22:00. This is the set of
    /// bars the detail chart draws and the hours the scrubber can land on.
    var openHours: [Int] {
        guard closesAt.hour > opensAt.hour else { return [] }
        return Array(opensAt.hour..<closesAt.hour)
    }
}
