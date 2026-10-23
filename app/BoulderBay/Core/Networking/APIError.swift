import Foundation

enum APIError: Error, Equatable {
    case badStatus(Int)
    /// A 409, carrying FastAPI's `detail` message (e.g. "You already have a home") for the UI.
    case conflict(String)
    case decoding(String)
}
