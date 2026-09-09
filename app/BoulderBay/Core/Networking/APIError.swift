import Foundation

enum APIError: Error, Equatable {
    case badStatus(Int)
    case decoding(String)
}
