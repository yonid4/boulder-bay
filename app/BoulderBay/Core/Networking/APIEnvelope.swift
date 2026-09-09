import Foundation

/// The API wraps collections in `{"data": [...]}`.
struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
}
