import Foundation

@testable import BoulderBay

/// Loads the JSON samples in `Fixtures/`. Each mirrors one endpoint's response body,
/// envelope included.
enum Fixture {
    private final class Anchor {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: Anchor.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Codable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder.api.decode(APIEnvelope<T>.self, from: data(name)).data
    }
}
