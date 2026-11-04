import SwiftUI

/// What `GymsView` draws for a given state, split out so snapshots needn't load anything: the
/// header, the search field, and the results over "Your gyms".
struct GymsContent: View {
    let gyms: [Gym]
    let memberships: Set<String>
    let pendingMemberships: Set<String>
    let loadState: AppModel.LoadState
    @Binding var query: String
    var membershipError: String?
    var onDismissError: () -> Void = {}
    var onRetry: () -> Void = {}
    var onOpenGym: (Gym) -> Void = { _ in }
    var onToggle: (Gym) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MenuButton()
                Text("Gyms")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            searchField
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if let membershipError {
                errorBanner(membershipError)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            // A list that failed to reload for another hour is still good here: this screen
            // shows nothing hour-specific. Only having no list at all stops it.
            if gyms.isEmpty, loadState != .loaded {
                noList
            } else {
                lists
            }
        }
        .background(Theme.background)
    }

    // MARK: Search

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            TextField(
                "Search gyms",
                text: $query,
                prompt: Text("Search gyms to add").foregroundStyle(Theme.textTertiary)
            )
            .font(.system(size: 16))
            .foregroundStyle(Theme.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.card)
                        .frame(width: 20, height: 20)
                        .background(Theme.borderSolid, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background {
            // On the shape, as a shadow on the whole field would fall on its contents too.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06))
        }
    }

    // MARK: Lists

    private var lists: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if hasQuery {
                    results
                }
                yourGyms
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var results: some View {
        let results = GymList.results(in: gyms, query: query)
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Results")
                .padding(.horizontal, 4)
            if results.isEmpty {
                Text("No gyms match \"\(query)\"")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                rows(results) { memberships.contains($0.slug) ? .added : .add }
            }
        }
    }

    private var yourGyms: some View {
        let members = GymList.members(of: gyms, memberships: memberships)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeading("Your gyms")
                Spacer(minLength: 0)
                Text(GymList.memberCountLabel(members.count))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 4)
            if members.isEmpty {
                Text(
                    "No gyms yet. Search above to add the gyms you belong to — they get priority on the map and a boost in Rankings."
                )
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                rows(members) { _ in .remove }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }

    private func rows(_ gyms: [Gym], action: @escaping (Gym) -> GymRow.Action) -> some View {
        VStack(spacing: 0) {
            ForEach(gyms) { gym in
                GymRow(
                    gym: gym,
                    action: action(gym),
                    isPending: pendingMemberships.contains(gym.slug),
                    onOpen: { onOpenGym(gym) },
                    onToggle: { onToggle(gym) }
                )
                if gym.id != gyms.last?.id {
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .background {
            // On the shape, as a shadow on the whole card would fall on the rows too.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadow.opacity(0.06), radius: 1, y: 1)
                .shadow(color: Theme.shadow.opacity(0.06), radius: 10, y: 6)
        }
    }

    // MARK: No list

    /// Loading, or the failure with a retry, in place of the lists.
    private var noList: some View {
        VStack(spacing: 12) {
            if case .failed(let message) = loadState {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: onRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.brandPrimary)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading gyms")
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error

    /// A failed toggle, already rolled back. Laid out like the map's failure banner, with a
    /// lighter shadow as it sits right under the search field.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Button("OK", action: onDismissError)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brandPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.shadow.opacity(0.06), radius: 10, y: 6)
        }
    }
}
