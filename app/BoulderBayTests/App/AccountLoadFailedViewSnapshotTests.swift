import SnapshotTesting
import SwiftUI
import Testing

@testable import BoulderBay

/// Reference images live in `__Snapshots__/`. To re-record after an intended visual change,
/// delete the affected PNGs and run the tests once; they fail while recording, then pass.
@MainActor
@Suite
struct AccountLoadFailedViewSnapshotTests {
    @Test func offline() {
        let view = AccountLoadFailedView(
            message: APIError.message(for: URLError(.notConnectedToInternet)),
            onRetry: {},
            onSignOut: {}
        )
        assertSnapshot(
            of: view,
            // A 393 × 852 pt phone. Small rendering differences between simulator OS
            // versions shouldn't fail CI.
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 393, height: 852))
        )
    }
}
