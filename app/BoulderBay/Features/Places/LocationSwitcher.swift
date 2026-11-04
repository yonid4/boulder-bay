import SwiftUI

/// The chip on the root screens that shows the selected place and switches between places.
/// Its menu lists every place and ends with "Edit places…", which opens the places sheet.
struct LocationSwitcher: View {
    /// In the order to list them (`AppModel.locationsInDisplayOrder`).
    let locations: [SavedLocation]
    let selected: SavedLocation?
    let onSelect: (SavedLocation) -> Void

    @Environment(\.showPlaces) private var showPlaces

    var body: some View {
        Menu {
            ForEach(locations) { location in
                // A menu's toggle draws the checkmark and keeps the kind's icon beside it.
                Toggle(isOn: selectionBinding(for: location)) {
                    Label(location.label, systemImage: location.kind.symbolName)
                }
            }
            Divider()
            Button("Edit places…") { showPlaces?() }
        } label: {
            LocationChip(location: selected)
        }
        .accessibilityLabel("Location")
        .accessibilityValue(selected?.label ?? "None")
    }

    private func selectionBinding(for location: SavedLocation) -> Binding<Bool> {
        Binding(
            get: { location.id == selected?.id },
            set: { _ in onSelect(location) }
        )
    }
}

/// What `LocationSwitcher` draws when closed, apart so snapshots can draw it: a menu's popup can't
/// be rendered in one. It matches `MenuButton`'s white, translucent look.
struct LocationChip: View {
    let location: SavedLocation?

    var body: some View {
        HStack(spacing: 8) {
            if let location {
                Image(systemName: location.kind.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brandPrimary)
                Text(location.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.card.opacity(0.9), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.12), radius: 12, y: 6)
    }
}

#Preview {
    LocationSwitcher(
        locations: [],
        selected: SavedLocation(
            id: UUID(), label: "Home", address: nil, latitude: 37.8, longitude: -122.3,
            isDefault: true, kind: .home
        ),
        onSelect: { _ in }
    )
    .padding()
    .background(Theme.background)
}
