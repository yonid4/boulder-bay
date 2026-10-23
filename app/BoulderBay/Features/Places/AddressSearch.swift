import Foundation
import MapKit

/// One row in the address search's suggestion list, as `MKLocalSearchCompleter` words it.
struct AddressSuggestion: Hashable, Identifiable, Sendable {
    let title: String
    let subtitle: String

    var id: Self { self }

    /// Title and subtitle on one line, for a search that has only the words to go on.
    var text: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

/// A place's address and coordinates, as the form sends them to the API.
struct PlaceAddress: Hashable, Sendable {
    /// `nil` only for an existing place that was saved without one.
    let address: String?
    let latitude: Double
    let longitude: Double
}

enum AddressSearchError: Error, Equatable {
    case notFound
}

/// The seam between the place form and MapKit, so the form is tested without the network.
@MainActor
protocol AddressSearching: AnyObject {
    /// Suggestions for what has been typed so far.
    func suggestions(for query: String) async throws -> [AddressSuggestion]
    /// The chosen suggestion's display address and coordinates.
    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceAddress
}

/// `MKLocalSearchCompleter` for suggestions, then `MKLocalSearch` to resolve the chosen one.
/// Both are biased toward the Bay Area, where every gym is.
@MainActor
final class MapKitAddressSearch: NSObject, AddressSearching {
    private let completer = MKLocalSearchCompleter()
    /// The caller waiting on the completer's next answer; a newer query cancels it.
    private var pending: CheckedContinuation<[AddressSuggestion], any Error>?
    /// The completer's latest answer, for a repeat of the same query.
    private var latest: [AddressSuggestion] = []
    /// The completions behind the suggestions shown, so a chosen one resolves exactly.
    private var completions: [AddressSuggestion: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.bayArea
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func suggestions(for query: String) async throws -> [AddressSuggestion] {
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else {
            finishPending(with: .failure(CancellationError()))
            completions = [:]
            return []
        }
        // The completer only calls back when the fragment changes.
        if fragment == completer.queryFragment, pending == nil {
            return latest
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                finishPending(with: .failure(CancellationError()))
                pending = continuation
                completer.queryFragment = fragment
            }
        } onCancel: {
            Task { @MainActor in self.finishPending(with: .failure(CancellationError())) }
        }
    }

    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceAddress {
        let request: MKLocalSearch.Request
        if let completion = completions[suggestion] {
            request = MKLocalSearch.Request(completion: completion)
        } else {
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = suggestion.text
        }
        request.region = Self.bayArea

        let response = try await MKLocalSearch(request: request).start()
        guard let placemark = response.mapItems.first?.placemark else {
            throw AddressSearchError.notFound
        }
        return PlaceAddress(
            address: Self.displayAddress(
                streetNumber: placemark.subThoroughfare,
                street: placemark.thoroughfare,
                city: placemark.locality,
                state: placemark.administrativeArea,
                fallback: suggestion.text
            ),
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }

    /// "2295 Harrison St, San Francisco, CA": short enough for a list row, without the country.
    /// Falls back to the suggestion's own words when MapKit gives no address parts.
    nonisolated static func displayAddress(
        streetNumber: String?, street: String?, city: String?, state: String?, fallback: String
    ) -> String {
        let line = [streetNumber, street].compactMap(trimmed).joined(separator: " ")
        let parts = [line, city, state].compactMap(trimmed)
        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }

    private nonisolated static func trimmed(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Records the completer's answer and hands it to whoever is waiting. Completions are
    /// kept across answers, since the completer can refine a list the user is already reading.
    private func completerDidUpdate() {
        latest = completer.results.map { completion in
            let suggestion = AddressSuggestion(title: completion.title, subtitle: completion.subtitle)
            completions[suggestion] = completion
            return suggestion
        }
        finishPending(with: .success(latest))
    }

    private func finishPending(with result: Result<[AddressSuggestion], any Error>) {
        pending?.resume(with: result)
        pending = nil
    }

    /// San Francisco to San Jose and across the bay, with room to spare.
    private static let bayArea = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.6, longitude: -122.2),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )
}

extension MapKitAddressSearch: MKLocalSearchCompleterDelegate {
    // The completer calls its delegate on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            completerDidUpdate()
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            finishPending(with: .failure(error))
        }
    }
}
