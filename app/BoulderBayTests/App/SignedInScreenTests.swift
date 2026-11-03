import Testing

@testable import BoulderBay

struct SignedInScreenTests {
    /// An empty list means nothing until the load succeeds, so nobody is sent to the
    /// first-place step early.
    @Test(arguments: [AppModel.LoadState.idle, .loading])
    func whileTheAccountLoadsItShowsASpinner(state: AppModel.LoadState) {
        #expect(SignedInScreen(state: state, hasLocations: false) == .loading)
    }

    @Test func aFailedLoadShowsItsMessage() {
        let screen = SignedInScreen(
            state: .failed("Couldn't reach the server."), hasLocations: false
        )

        #expect(screen == .failed("Couldn't reach the server."))
    }

    @Test func aLoadedAccountWithoutPlacesAddsOneFirst() {
        #expect(SignedInScreen(state: .loaded, hasLocations: false) == .firstPlace)
    }

    @Test func aLoadedAccountWithPlacesGetsTheShell() {
        #expect(SignedInScreen(state: .loaded, hasLocations: true) == .shell)
    }
}
