import Foundation

/// Stateless fetch of one gym's detail. Only the detail screen reads it, so it isn't a
/// store.
struct GymDetailService: Sendable {
    let api: any APIClient

    func detail(slug: String) async throws -> GymDetail {
        try await api.gym(slug: slug)
    }
}
