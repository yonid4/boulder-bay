import Foundation

enum APIError: Error, Equatable {
    case badStatus(Int)
    /// A 409, carrying FastAPI's `detail` message (e.g. "You already have a home") for the UI.
    case conflict(String)
    case decoding(String)
}

extension APIError {
    /// A sentence for the UI. A 409's `detail` is already written for people, so it's shown
    /// as it is.
    static func message(for error: any Error) -> String {
        switch error {
        case APIError.conflict(let message):
            message
        case APIError.badStatus(401):
            "Your session has expired. Sign in again."
        case APIError.badStatus(let code):
            "The server returned an error (\(code))."
        case APIError.decoding:
            "The server sent something unexpected."
        default:
            "Couldn't reach the server. Check your connection."
        }
    }
}
