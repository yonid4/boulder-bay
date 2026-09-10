import MapKit
import SwiftUI

/// Address (opens Apple Maps), hours today, and rates — the plain list under the card.
struct InfoRows: View {
    let model: GymDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let gym = model.gym {
                Button {
                    MKMapItem.openInAppleMaps(name: gym.name, latitude: gym.latitude, longitude: gym.longitude)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            label("Address")
                            Text(gym.address ?? gym.city)
                                .font(Typography.rowBody)
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 12) {
                                if let travel = model.travelText {
                                    Text(travel).foregroundStyle(Theme.textSecondary)
                                }
                                if let distance = model.distanceText {
                                    Text(distance).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .font(Typography.caption)
                        }
                        Spacer(minLength: 0)
                        Text("Open in Maps")
                            .font(Typography.label)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface, in: Capsule())
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Apple Maps")
                divider
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    label("Hours today")
                    Text(model.hoursText)
                        .font(Typography.rowBody)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
                Text(model.openStatusText)
                    .font(Typography.label)
                    .foregroundStyle(model.isOpen ? Theme.Busyness.quiet : Theme.Busyness.packed)
            }
            .padding(.vertical, 14)
            divider

            VStack(alignment: .leading, spacing: 4) {
                label("Rates")
                HStack(spacing: 18) {
                    if let day = model.dayPassText {
                        rate("Day pass", day)
                    }
                    if let monthly = model.monthlyText {
                        rate("Monthly", monthly)
                    }
                    if model.dayPassText == nil, model.monthlyText == nil {
                        Text("Not listed").font(Typography.rowBody).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let note = model.rateNote {
                    Text(note).font(Typography.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Typography.caption).foregroundStyle(Theme.textTertiary)
    }

    private func rate(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(Theme.textPrimary)
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
        }
        .font(Typography.rowBody)
    }
}
