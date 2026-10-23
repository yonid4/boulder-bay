import Testing

@testable import BoulderBay

@Suite
struct AddressSearchTests {
    @Test func displayAddressIsStreetCityAndState() {
        let address = MapKitAddressSearch.displayAddress(
            streetNumber: "2295",
            street: "Harrison St",
            city: "San Francisco",
            state: "CA",
            fallback: "unused"
        )
        #expect(address == "2295 Harrison St, San Francisco, CA")
    }

    @Test func displayAddressSkipsMissingParts() {
        let address = MapKitAddressSearch.displayAddress(
            streetNumber: nil, street: nil, city: "Oakland", state: "CA", fallback: "unused"
        )
        #expect(address == "Oakland, CA")
    }

    @Test func displayAddressFallsBackWithoutAnyParts() {
        let address = MapKitAddressSearch.displayAddress(
            streetNumber: nil, street: " ", city: nil, state: nil, fallback: "Somewhere"
        )
        #expect(address == "Somewhere")
    }

    @Test func suggestionFallbackJoinsTitleAndSubtitle() {
        let full = AddressSuggestion(title: "Mission Cliffs", subtitle: "San Francisco, CA")
        let bare = AddressSuggestion(title: "Oakland", subtitle: "")
        #expect(full.text == "Mission Cliffs, San Francisco, CA")
        #expect(bare.text == "Oakland")
    }
}
