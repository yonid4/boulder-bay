import Foundation

/// Thin `URLSession` + `Codable` wrapper. No third-party networking layer.
struct APIClient: Sendable {
    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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

    // MARK: - Requests

    func get<T: Decodable & Sendable>(
        _ path: String, queryItems: [URLQueryItem] = [], as type: T.Type
    ) async throws -> T {
        try decode(type, from: await send(method: "GET", path: path, queryItems: queryItems))
    }

    func post<T: Decodable & Sendable>(
        _ path: String, body: some Encodable & Sendable, as type: T.Type
    ) async throws -> T {
        try decode(type, from: await send(method: "POST", path: path, body: body))
    }

    /// A `POST` whose response has no body worth reading, such as a 204.
    func post(_ path: String) async throws {
        _ = try await send(method: "POST", path: path)
    }

    func patch<T: Decodable & Sendable>(
        _ path: String, body: some Encodable & Sendable, as type: T.Type
    ) async throws -> T {
        try decode(type, from: await send(method: "PATCH", path: path, body: body))
    }

    /// A `DELETE` whose response has no body worth reading, such as a 204.
    func delete(_ path: String) async throws {
        _ = try await send(method: "DELETE", path: path)
    }

    // MARK: - Gyms

    /// Gyms with busyness resolved for `at`, or for now when `at` is `nil`.
    func gyms(at: Date? = nil) async throws -> [Gym] {
        // The backend rejects an `at` without an offset; ISO 8601 in UTC always carries one.
        let queryItems = at.map { [URLQueryItem(name: "at", value: $0.formatted(.iso8601))] } ?? []
        return try await get("/api/gyms", queryItems: queryItems, as: APIEnvelope<[Gym]>.self).data
    }

    /// A gym's logo bytes, or `.notModified` when `ifNoneMatch` still matches its `ETag`.
    /// A gym with no logo, or an unknown or inactive slug, is `.badStatus(404)`.
    func logo(slug: String, ifNoneMatch: String? = nil) async throws -> LogoResponse {
        let headers = ifNoneMatch.map { ["If-None-Match": $0] } ?? [:]
        let (data, response) = try await exchange(
            method: "GET", path: "/api/gyms/\(slug)/logo", headers: headers,
            acceptsNotModified: true
        )
        if response?.statusCode == 304 { return .notModified }
        return .image(data, etag: response?.value(forHTTPHeaderField: "ETag"))
    }

    // MARK: - Profile

    /// The signed-in user's profile. A missing profile row is `.badStatus(404)`.
    func me() async throws -> UserProfile {
        try await get("/api/me", as: APIEnvelope<UserProfile>.self).data
    }

    // MARK: - Memberships

    /// Slugs of the gyms the user belongs to, ordered by gym name.
    func memberships() async throws -> [String] {
        try await get("/api/me/memberships", as: APIEnvelope<[String]>.self).data
    }

    /// Idempotent. An unknown or inactive slug is `.badStatus(404)`.
    func addMembership(gymSlug: String) async throws {
        try await post("/api/me/memberships/\(gymSlug)")
    }

    /// Idempotent. An unknown or inactive slug is `.badStatus(404)`.
    func removeMembership(gymSlug: String) async throws {
        try await delete("/api/me/memberships/\(gymSlug)")
    }

    // MARK: - Saved locations

    /// The user's places, in creation order.
    func locations() async throws -> [SavedLocation] {
        try await get("/api/me/locations", as: APIEnvelope<[SavedLocation]>.self).data
    }

    /// A missing id, or another user's, is `.badStatus(404)`.
    func location(id: UUID) async throws -> SavedLocation {
        try await get(Self.locationPath(id), as: APIEnvelope<SavedLocation>.self).data
    }

    /// The first place becomes the default. Label / home / work clashes are `.conflict`.
    func createLocation(_ location: CreateSavedLocation) async throws -> SavedLocation {
        try await post("/api/me/locations", body: location, as: APIEnvelope<SavedLocation>.self)
            .data
    }

    /// Changes only the fields `changes` sets. Label / home / work clashes are `.conflict`.
    func updateLocation(
        id: UUID, _ changes: UpdateSavedLocation
    ) async throws -> SavedLocation {
        try await patch(Self.locationPath(id), body: changes, as: APIEnvelope<SavedLocation>.self)
            .data
    }

    /// Deleting the only place is `.conflict`; deleting the default promotes the oldest other.
    func deleteLocation(id: UUID) async throws {
        try await delete(Self.locationPath(id))
    }

    // MARK: - Transport

    private static func locationPath(_ id: UUID) -> String {
        "/api/me/locations/\(id.uuidString.lowercased())"
    }

    /// Sends one request and returns its body, mapping non-2xx statuses to `APIError`.
    private func send(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> Data {
        try await exchange(method: method, path: path, queryItems: queryItems, body: body).data
    }

    /// Sends one request and returns its raw body and response, mapping non-2xx statuses to
    /// `APIError`. `headers` are added as given. With `acceptsNotModified` a 304 is a success
    /// with an empty body, so a conditional request can tell "unchanged" from a failure.
    private func exchange(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        headers: [String: String] = [:],
        acceptsNotModified: Bool = false
    ) async throws -> (data: Data, response: HTTPURLResponse?) {
        var url = baseURL.appending(path: path)
        if !queryItems.isEmpty { url.append(queryItems: queryItems) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try Self.jsonEncoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<300).contains(status),
            !(acceptsNotModified && status == 304)
        {
            throw Self.error(forStatus: status, body: data)
        }
        return (data, http)
    }

    private static func error(forStatus status: Int, body: Data) -> APIError {
        // FastAPI's HTTPException body is `{"detail": "..."}`.
        if status == 409, let detail = try? jsonDecoder.decode(ErrorDetail.self, from: body) {
            return .conflict(detail.detail)
        }
        return .badStatus(status)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

/// What `APIClient.logo(slug:ifNoneMatch:)` got back.
enum LogoResponse: Equatable, Sendable {
    /// The image bytes, and the `ETag` to send as `If-None-Match` next time.
    case image(Data, etag: String?)
    /// A 304: the logo still matches the `ETag` that was sent.
    case notModified
}

private struct ErrorDetail: Decodable {
    let detail: String
}
