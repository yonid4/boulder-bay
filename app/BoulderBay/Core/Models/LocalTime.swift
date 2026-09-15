import Foundation

/// A local wall-clock time with no date or timezone.
struct LocalTime: Codable, Hashable, Sendable {
    let hour: Int
    let minute: Int
    let second: Int

    init?(hour: Int, minute: Int, second: Int) {
        guard (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second)
        else {
            return nil
        }

        self.hour = hour
        self.minute = minute
        self.second = second
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)

        guard value.utf8.count == 8,
              parts.count == 3,
              parts.allSatisfy({ $0.utf8.count == 2 }),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]),
              let time = Self(hour: hour, minute: minute, second: second)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a valid time in HH:mm:ss format"
            )
        }

        self = time
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d:%02d", hour, minute, second))
    }
}
