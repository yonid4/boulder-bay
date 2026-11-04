import Foundation

@testable import BoulderBay

/// A small stand-in for the backend's places API behind `StubURLProtocol`, moving the default
/// the way the real one does. It stays registered for its host until the next test's server
/// replaces it, so give each suite its own host and mark the suite `.serialized`.
final class PlacesTestServer: Sendable {
    struct Place: Sendable {
        var id: UUID
        var label: String
        var address: String?
        var isDefault: Bool
        var kind: String

        fileprivate var json: String {
            let address = address.map { #""\#($0)""# } ?? "null"
            return """
                {"id": "\(id.uuidString.lowercased())", "label": "\(label)", "address": \(address), \
                "latitude": 37.8, "longitude": -122.2, "is_default": \(isDefault), "kind": "\(kind)"}
                """
        }
    }

    struct Request: Sendable {
        let method: String
        let path: String
        fileprivate let bodyData: Data?

        var body: NSDictionary? {
            bodyData.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? NSDictionary }
        }
    }

    /// When set, every POST, PATCH and DELETE answers 409 with this message.
    let writeConflict = LockedBox<String?>(nil)
    /// When true, `GET /api/me/locations` answers 500.
    let failLocationReads = LockedBox(false)

    private let host: String
    private let places: LockedBox<[Place]>
    private let log = LockedBox<[Request]>([])

    init(host: String, places: [Place]) {
        self.host = host
        self.places = LockedBox(places)
        StubURLProtocol.setHandler(forHost: host) { [self] request in
            handle(request)
        }
    }

    var requests: [Request] {
        log.withValue { $0 }
    }

    var locationReads: Int {
        requests.filter { $0.method == "GET" && $0.path == "/api/me/locations" }.count
    }

    var profileReads: Int {
        requests.filter { $0.method == "GET" && $0.path == "/api/me" }.count
    }

    func makeAPIClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: URLSession(configuration: configuration),
            accessToken: { "test-token" }
        )
    }

    private func handle(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let logged = Request(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            bodyData: request.bodyData
        )
        log.withValue { $0.append(logged) }

        if logged.method != "GET", let message = writeConflict.withValue({ $0 }) {
            return respond(request, status: 409, body: #"{"detail": "\#(message)"}"#)
        }

        switch (logged.method, logged.path) {
        case ("GET", "/api/me"):
            return respond(
                request,
                status: 200,
                body: #"{"data": {"id": "7878e808-a48f-4649-8a65-3feb6029a591", "display_name": "Alex"}}"#
            )
        case ("GET", "/api/me/memberships"):
            return respond(request, status: 200, body: #"{"data": []}"#)
        case ("GET", "/api/me/locations"):
            if failLocationReads.withValue({ $0 }) {
                return respond(request, status: 500, body: "")
            }
            let list = places.withValue { $0.map(\.json).joined(separator: ", ") }
            return respond(request, status: 200, body: #"{"data": [\#(list)]}"#)
        case ("POST", "/api/me/locations"):
            return create(request, body: logged.body)
        case ("PATCH", _):
            return update(request, path: logged.path, body: logged.body)
        case ("DELETE", _):
            return delete(request, path: logged.path)
        default:
            return respond(request, status: 404, body: "")
        }
    }

    private func create(_ request: URLRequest, body: NSDictionary?) -> (HTTPURLResponse, Data) {
        let place = Place(
            id: UUID(),
            label: body?["label"] as? String ?? "",
            address: body?["address"] as? String,
            isDefault: false,
            kind: body?["kind"] as? String ?? "other"
        )
        places.withValue { $0.append(place) }
        return respond(request, status: 201, body: #"{"data": \#(place.json)}"#)
    }

    private func update(
        _ request: URLRequest, path: String, body: NSDictionary?
    ) -> (HTTPURLResponse, Data) {
        let updated = places.withValue { places -> Place? in
            guard let index = places.firstIndex(where: { path.hasSuffix(id: $0.id) }) else {
                return nil
            }
            if let label = body?["label"] as? String { places[index].label = label }
            if body?["make_default"] as? Bool == true {
                for other in places.indices { places[other].isDefault = other == index }
            }
            return places[index]
        }
        guard let updated else { return respond(request, status: 404, body: "") }
        return respond(request, status: 200, body: #"{"data": \#(updated.json)}"#)
    }

    /// Deleting the default promotes the oldest other place.
    private func delete(_ request: URLRequest, path: String) -> (HTTPURLResponse, Data) {
        places.withValue { places in
            places.removeAll { path.hasSuffix(id: $0.id) }
            if !places.isEmpty, !places.contains(where: \.isDefault) {
                places[0].isDefault = true
            }
        }
        return respond(request, status: 204, body: "")
    }

    private func respond(
        _ request: URLRequest, status: Int, body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }
}

private extension String {
    func hasSuffix(id: UUID) -> Bool {
        hasSuffix("/\(id.uuidString.lowercased())")
    }
}
