import Foundation

@testable import BoulderBay

/// Canned address search, so the place form is tested without MapKit or the network.
@MainActor
final class FakeAddressSearch: AddressSearching {
    /// Suggestions per query; an unknown query has none.
    var suggestionsByQuery: [String: [AddressSuggestion]] = [:]
    /// What each suggestion resolves to; an unknown one throws `AddressSearchError.notFound`.
    var resolutions: [AddressSuggestion: PlaceAddress] = [:]
    var suggestionsError: (any Error)?
    private(set) var queries: [String] = []

    func suggestions(for query: String) async throws -> [AddressSuggestion] {
        queries.append(query)
        if let suggestionsError { throw suggestionsError }
        return suggestionsByQuery[query] ?? []
    }

    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceAddress {
        guard let address = resolutions[suggestion] else { throw AddressSearchError.notFound }
        return address
    }
}
