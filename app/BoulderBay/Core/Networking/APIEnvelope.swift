import Foundation

/// Every response body is wrapped as `{"data": …}` — collections and single objects
/// alike — so a payload can grow metadata later without breaking clients.
struct APIEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let data: T

    init(_ data: T) {
        self.data = data
    }
}
