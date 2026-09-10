import MapKit
import SwiftUI

/// A resolved place: what `MKLocalSearch` gives back for a chosen completion.
struct PlaceResult: Hashable, Sendable {
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double
}

/// Wraps `MKLocalSearchCompleter`, biased to the Bay Area. Completions update as the
/// query changes; `resolve` turns one into coordinates.
@MainActor
@Observable
final class PlaceSearch: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private(set) var completions: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()

    /// Roughly Marin to San Jose.
    static let bayArea = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.65, longitude: -122.2),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    override init() {
        super.init()
        completer.delegate = self
        completer.region = Self.bayArea
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed != oldValue.trimmingCharacters(in: .whitespaces) else { return }
            if trimmed.isEmpty {
                completions = []
                completer.cancel()
            } else {
                isSearching = true
                completer.queryFragment = trimmed
            }
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> PlaceResult {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { throw CocoaError(.fileNoSuchFile) }
        let coordinate = item.placemark.coordinate
        let address = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return PlaceResult(
            title: item.name ?? completion.title,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    // MARK: MKLocalSearchCompleterDelegate
    // MapKit calls these on the main queue; the `@preconcurrency` conformance lets the
    // main-actor class implement them directly.

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completions = []
        isSearching = false
    }
}

/// Search box plus a dropdown of completions; picking one calls `onPick`.
struct LocationSearchField: View {
    @Bindable var search: PlaceSearch
    let onPick: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(spacing: 8) {
            SearchField(text: $search.query, placeholder: "Search an address or place")
            if !search.completions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(search.completions.prefix(6).enumerated()), id: \.offset) { index, completion in
                        Button {
                            onPick(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(Typography.rowTitle)
                                    .foregroundStyle(Theme.textPrimary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(Typography.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < min(search.completions.count, 6) - 1 {
                            Divider().background(Theme.divider).padding(.leading, 16)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
                .floatingShadow()
            }
        }
    }
}
