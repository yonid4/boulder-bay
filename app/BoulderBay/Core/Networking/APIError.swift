import Foundation

enum APIError: Error, Equatable, Sendable {
    /// The request never produced an HTTP response (offline, DNS, timeout).
    case transport(String)
    /// A 401 — the bearer token was missing, expired, or rejected.
    case unauthorized
    /// Any other non-2xx status.
    case badStatus(Int)
    case decoding(String)
    case encoding(String)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .transport(let message): "Couldn't reach the server. \(message)"
        case .unauthorized: "Please sign in again."
        case .badStatus(let code): "The server returned an error (\(code))."
        case .decoding: "The server sent something unexpected."
        case .encoding: "Couldn't prepare the request."
        }
    }
}
