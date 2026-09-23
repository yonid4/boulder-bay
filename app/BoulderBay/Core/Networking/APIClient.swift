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
    private let accessToken: @Sendable () async throws -> String

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        session: URLSession = .shared,
        accessToken: @escaping @Sendable () async throws -> String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
    }

    func get<T: Decodable & Sendable>(
        _ path: String, queryItems: [URLQueryItem] = [], as type: T.Type
    ) async throws -> T {
        var url = baseURL.appending(path: path)
        if !queryItems.isEmpty { url.append(queryItems: queryItems) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await send(request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }

        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Gyms with busyness resolved for `at`, or for now when `at` is `nil`.
    func gyms(at: Date? = nil) async throws -> [Gym] {
        // The backend rejects an `at` without an offset; ISO 8601 in UTC always carries one.
        let queryItems = at.map { [URLQueryItem(name: "at", value: $0.formatted(.iso8601))] } ?? []
        return try await get("/api/gyms", queryItems: queryItems, as: APIEnvelope<[Gym]>.self).data
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        return try await session.data(for: request)
    }
}
