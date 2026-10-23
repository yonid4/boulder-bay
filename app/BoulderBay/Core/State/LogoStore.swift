import Foundation
import UIKit

/// Gym logos, held in memory for the life of the process.
///
/// Logos live in the database (root `CLAUDE.md`) and come from `GET /api/gyms/{slug}/logo`
/// through `APIClient`, so the bearer token is attached. Nothing reaches disk: the client's
/// session has no `URLCache`, and the cache here dies with the process — the v1 choice. Each
/// slug is fetched at most once per launch; concurrent asks for one slug share one request.
///
/// A 404 (the gym has no logo) and bytes that don't decode are remembered as "no logo" for
/// the launch. Any other failure — offline, a 5xx, no session yet — is not remembered, so
/// the next ask retries.
actor LogoStore {
    private enum Entry: Sendable {
        case logo(UIImage)
        case none

        var image: UIImage? {
            if case .logo(let image) = self { image } else { nil }
        }
    }

    private let client: APIClient
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry?, Never>] = [:]

    /// `client` should use `makeSession()`, or another session without a disk cache.
    init(client: APIClient) {
        self.client = client
    }

    /// A session that caches nothing, so logo bytes never touch disk.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// The gym's logo, or `nil` when it has none or it couldn't be loaded.
    func logo(for slug: String) async -> UIImage? {
        if let entry = entries[slug] { return entry.image }
        if let task = inFlight[slug] { return await task.value?.image }

        let client = client
        let task = Task { await Self.fetch(slug, with: client) }
        inFlight[slug] = task
        let entry = await task.value
        inFlight[slug] = nil
        if let entry { entries[slug] = entry }
        return entry?.image
    }

    /// The entry to remember, or `nil` for a failure worth retrying.
    private static func fetch(_ slug: String, with client: APIClient) async -> Entry? {
        do {
            // Nothing is cached across launches, so there is never an ETag worth sending.
            guard case .image(let data, _) = try await client.logo(slug: slug) else { return nil }
            return UIImage(data: data).map(Entry.logo) ?? Entry.none
        } catch APIError.badStatus(404) {
            return Entry.none
        } catch {
            return nil
        }
    }
}
