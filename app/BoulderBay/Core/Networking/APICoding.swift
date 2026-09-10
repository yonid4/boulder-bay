import Foundation

/// The one decoder/encoder pair the API layer uses. Keys are spelled out per model in
/// `CodingKeys` (no automatic snake-case conversion), so the only shared concern here
/// is dates: ISO 8601, with or without fractional seconds, since FastAPI emits
/// microseconds and hand-written fixtures usually don't.
extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601.withFractionalSeconds.date(from: raw)
                ?? ISO8601.plain.date(from: raw)
            {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(raw)")
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.plain.string(from: date))
        }
        return encoder
    }()
}

/// `ISO8601DateFormatter` is documented thread-safe but not annotated `Sendable`, hence
/// `nonisolated(unsafe)`: the instances are configured once here and never mutated.
private enum ISO8601 {
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
