import Foundation
import os

/// Answers `URLSession` requests from a canned handler so `LiveAPIClient` can be tested
/// without a server. Install with `StubURLProtocol.session()`; set the handler per test.
/// The handler is process-global, so suites using it must be `.serialized`.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, body: Data)

    private static let handler = OSAllocatedUnfairLock<Handler?>(initialState: nil)
    private static let requests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    static func respond(_ handler: @escaping Handler) {
        Self.handler.withLock { $0 = handler }
        requests.withLock { $0.removeAll() }
    }

    /// Convenience: every request gets the same status and body.
    static func respond(status: Int = 200, body: Data = Data()) {
        respond { _ in (status, body) }
    }

    /// Every request seen since the last `respond`, in order.
    static var recordedRequests: [URLRequest] { requests.withLock { $0 } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Self.requests.withLock { $0.append(request) }
        guard let handler = Self.handler.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// `httpBody` is dropped by the URL loading system before a protocol sees it; the
    /// bytes arrive as a stream instead.
    var bodyBytes: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
