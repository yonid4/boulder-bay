import Foundation

/// The app's view of the FastAPI backend — the planned endpoints from
/// `boulder_bay_plan.md`, one method each. `LiveAPIClient` speaks HTTP;
/// `MockAPIClient` serves the seed data in-process. Everything above this protocol
/// (stores, view models, previews, tests) is written against it and never knows which.
///
/// Not here yet, deliberately: `/api/me/prefs` — the ranking weights have no UI in v1.
protocol APIClient: Sendable {
    // Gyms
    func gyms() async throws -> [Gym]
    func gym(slug: String) async throws -> GymDetail

    // Rankings — `at` nil means "right now"; a date asks for the curve's forecast.
    func rankings(locationID: UUID, at: Date?) async throws -> Rankings

    // Me
    func me() async throws -> UserProfile
    func memberships() async throws -> [String]
    /// Replaces the whole set in one call and returns the stored result.
    func updateMemberships(_ slugs: [String]) async throws -> [String]
    func locations() async throws -> [SavedLocation]
    func createLocation(_ location: NewSavedLocation) async throws -> SavedLocation
    func deleteLocation(id: UUID) async throws
}
