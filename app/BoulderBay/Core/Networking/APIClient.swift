import Foundation

/// Thin `URLSession` + `Codable` wrapper. No third-party networking layer.
struct APIClient: Sendable {
    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func gyms() async throws -> [Gym] {
        try await get("/api/gyms", as: APIEnvelope<[Gym]>.self).data
    }
}
