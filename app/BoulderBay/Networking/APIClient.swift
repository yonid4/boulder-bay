import Foundation

enum APIError: Error, Equatable {
    case badStatus(Int)
    case decoding(String)
}

/// Thin `URLSession` + `Codable` wrapper. No third-party networking layer.
struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func get<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appending(path: path))

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func gyms() async throws -> [Gym] {
        try await get("/api/gyms", as: APIEnvelope<[Gym]>.self).data
    }
}
