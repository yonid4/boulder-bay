import Foundation

/// A transport-neutral description of one API call. `LiveAPIClient` turns it into a
/// `URLRequest`; tests can assert on it without touching the network.
struct APIRequest: Hashable, Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    let method: Method
    /// Path relative to the base URL, starting with `/`.
    let path: String
    let query: [URLQueryItem]
    let body: Data?

    init(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    static func get(_ path: String, query: [URLQueryItem] = []) -> APIRequest {
        APIRequest(.get, path, query: query)
    }

    static func post(_ path: String, json body: some Encodable) throws -> APIRequest {
        APIRequest(.post, path, body: try encode(body))
    }

    static func put(_ path: String, json body: some Encodable) throws -> APIRequest {
        APIRequest(.put, path, body: try encode(body))
    }

    static func delete(_ path: String) -> APIRequest {
        APIRequest(.delete, path)
    }

    private static func encode(_ body: some Encodable) throws -> Data {
        do {
            return try JSONEncoder.api.encode(body)
        } catch {
            throw APIError.encoding(String(describing: error))
        }
    }
}

extension APIRequest {
    /// Builds the outgoing request. The bearer token is the Supabase access token;
    /// FastAPI verifies its ES256 signature against the project's JWKS.
    func urlRequest(baseURL: URL, bearerToken: String?) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        var request = URLRequest(url: components?.url ?? baseURL.appending(path: path))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
