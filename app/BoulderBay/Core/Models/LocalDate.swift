import Foundation

/// A Gregorian calendar date with no time or timezone.
struct LocalDate: Codable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }

        let daysInMonth = switch month {
        case 2: Self.isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
        guard (1...daysInMonth).contains(day) else { return nil }

        self.year = year
        self.month = month
        self.day = day
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)

        guard value.utf8.count == 10,
              parts.count == 3,
              parts[0].utf8.count == 4,
              parts[1].utf8.count == 2,
              parts[2].utf8.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = Self(year: year, month: month, day: day)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a valid date in yyyy-MM-dd format"
            )
        }

        self = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    }
}
