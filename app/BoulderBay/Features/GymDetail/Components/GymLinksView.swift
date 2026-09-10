import SwiftUI

/// Website (primary) and Sign waiver (secondary, only when the gym has one).
struct GymLinksView: View {
    let gym: Gym

    var body: some View {
        HStack(spacing: 10) {
            if let website = gym.websiteURL {
                Link(destination: website) { Text("Website") }
                    .buttonStyle(PrimaryButtonStyle(height: 50))
            }
            if let waiver = gym.waiverURL {
                Link(destination: waiver) { Text("Sign waiver") }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
            }
        }
    }
}

#Preview {
    GymLinksView(gym: PreviewData.belmont).padding().background(Theme.background)
}
