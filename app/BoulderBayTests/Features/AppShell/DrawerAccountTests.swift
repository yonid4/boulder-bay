import Foundation
import Testing

@testable import BoulderBay

struct DrawerAccountTests {
    private let profile = UserProfile(
        id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
        displayName: "Alex Chen"
    )

    @Test func loadedProfileShowsNameInitialsAndEmail() {
        let account = DrawerAccount(profile: profile, state: .loaded, email: "alex@example.com")

        #expect(account.name == "Alex Chen")
        #expect(account.initials == "AC")
        #expect(account.detail == "alex@example.com")
    }

    @Test func withoutAnEmailThereIsNoDetailLine() {
        let account = DrawerAccount(profile: profile, state: .loaded, email: nil)

        #expect(account.detail == nil)
    }

    /// The profile is nil until `bootstrap()` succeeds; the drawer still opens meanwhile.
    @Test(arguments: [AppModel.LoadState.idle, .loading])
    func beforeTheProfileLoadsItShowsAGenericAccount(state: AppModel.LoadState) {
        let account = DrawerAccount(profile: nil, state: state, email: "alex@example.com")

        #expect(account.name == "Your account")
        #expect(account.initials.isEmpty)
        #expect(account.detail == "alex@example.com")
    }

    /// `AppModel` already wrote the failure with `APIError.message(for:)`.
    @Test func aFailedLoadShowsItsMessage() {
        let message = APIError.message(for: APIError.badStatus(500))
        let account = DrawerAccount(profile: nil, state: .failed(message), email: "alex@example.com")

        #expect(account.name == "Your account")
        #expect(account.initials.isEmpty)
        #expect(account.detail == message)
    }
}
