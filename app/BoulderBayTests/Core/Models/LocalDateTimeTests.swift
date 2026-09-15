import Foundation
import Testing

@testable import BoulderBay

struct LocalDateTimeTests {
    @Test func localDateRoundTripsCanonicalWireValue() throws {
        let date = try #require(LocalDate(year: 2024, month: 2, day: 29))

        let encoded = try JSONEncoder().encode(date)
        let decoded = try JSONDecoder().decode(LocalDate.self, from: encoded)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"2024-02-29\"")
        #expect(decoded == date)
    }

    @Test func localDateRejectsImpossibleAndMalformedValues() {
        #expect(LocalDate(year: 2023, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 2024, month: 13, day: 1) == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalDate.self, from: Data("\"2026-9-14\"".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalDate.self, from: Data("\"2026-02-29\"".utf8))
        }
    }

    @Test func localTimeRoundTripsCanonicalWireValue() throws {
        let time = try #require(LocalTime(hour: 6, minute: 5, second: 4))

        let encoded = try JSONEncoder().encode(time)
        let decoded = try JSONDecoder().decode(LocalTime.self, from: encoded)

        #expect(String(decoding: encoded, as: UTF8.self) == "\"06:05:04\"")
        #expect(decoded == time)
    }

    @Test func localTimeRejectsOutOfRangeAndMalformedValues() {
        #expect(LocalTime(hour: 24, minute: 0, second: 0) == nil)
        #expect(LocalTime(hour: 12, minute: 60, second: 0) == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalTime.self, from: Data("\"6:00:00\"".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalTime.self, from: Data("\"23:59:60\"".utf8))
        }
    }
}
