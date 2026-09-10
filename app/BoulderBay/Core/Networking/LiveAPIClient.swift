import Foundation

/// `URLSession` + `Codable` against the FastAPI backend. No third-party networking.
///
/// The endpoint methods that satisfy `APIClient` live in `Endpoints/`, grouped the way
/// the routes are; this file is only the transport.
struct LiveAPIClient: APIClient {
    typealias TokenProvider = @Sendable () async -> String?

    let baseURL: URL
    let session: URLSession
    /// Supplies the current Supabase access token, refreshed if needed. Returns nil when
    /// signed out, in which case the request goes out unauthenticated and the backend
    /// answers 401.
    let tokenProvider: TokenProvider

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// Sends a request and decodes the `{"data": …}` envelope around `T`.
    func send<T: Codable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let data = try await perform(request)
        do {
            return try JSONDecoder.api.decode(APIEnvelope<T>.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request whose response body is irrelevant (e.g. a 204 on DELETE).
    func send(_ request: APIRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: APIRequest) async throws -> Data {
        let urlRequest = request.urlRequest(baseURL: baseURL, bearerToken: await tokenProvider())
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401: throw APIError.unauthorized
            default: throw APIError.badStatus(http.statusCode)
            }
        }
        return data
    }
}
