import Foundation
import os

@testable import BoulderBay

/// Wraps a `MockAPIClient`, recording every call and optionally failing the next one.
/// Stores and view models are tested through this.
final class SpyAPIClient: APIClient {
    enum Call: Equatable, Sendable {
        case gyms
        case gym(String)
        case rankings(UUID, Date?)
        case me
        case memberships
        case updateMemberships([String])
        case locations
        case createLocation(String)
        case deleteLocation(UUID)
    }

    let inner: MockAPIClient
    private let state = OSAllocatedUnfairLock<(calls: [Call], failure: APIError?)>(initialState: ([], nil))

    init(inner: MockAPIClient = MockAPIClient()) {
        self.inner = inner
    }

    var calls: [Call] { state.withLock { $0.calls } }

    /// The next call throws this error, then behaviour returns to normal.
    func failNext(with error: APIError = .badStatus(500)) {
        state.withLock { $0.failure = error }
    }

    private func record(_ call: Call) throws {
        let failure: APIError? = state.withLock { state in
            state.calls.append(call)
            let pending = state.failure
            state.failure = nil
            return pending
        }
        if let failure { throw failure }
    }

    func gyms() async throws -> [Gym] {
        try record(.gyms)
        return try await inner.gyms()
    }

    func gym(slug: String) async throws -> GymDetail {
        try record(.gym(slug))
        return try await inner.gym(slug: slug)
    }

    func rankings(locationID: UUID, at: Date?) async throws -> Rankings {
        try record(.rankings(locationID, at))
        return try await inner.rankings(locationID: locationID, at: at)
    }

    func me() async throws -> UserProfile {
        try record(.me)
        return try await inner.me()
    }

    func memberships() async throws -> [String] {
        try record(.memberships)
        return try await inner.memberships()
    }

    func updateMemberships(_ slugs: [String]) async throws -> [String] {
        try record(.updateMemberships(slugs.sorted()))
        return try await inner.updateMemberships(slugs)
    }

    func locations() async throws -> [SavedLocation] {
        try record(.locations)
        return try await inner.locations()
    }

    func createLocation(_ location: NewSavedLocation) async throws -> SavedLocation {
        try record(.createLocation(location.label))
        return try await inner.createLocation(location)
    }

    func deleteLocation(id: UUID) async throws {
        try record(.deleteLocation(id))
        try await inner.deleteLocation(id: id)
    }
}
