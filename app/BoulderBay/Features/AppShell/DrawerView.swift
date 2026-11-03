import SwiftUI

/// What the drawer's account card shows. `AppModel.profile` is nil until `bootstrap()`
/// succeeds, so the card has a generic form for loading and for a failed load.
struct DrawerAccount: Equatable {
    let name: String
    /// Empty means no name yet; the avatar shows a person glyph instead.
    let initials: String
    /// The email under the name, or why the profile didn't load.
    let detail: String?

    init(name: String, initials: String, detail: String?) {
        self.name = name
        self.initials = initials
        self.detail = detail
    }

    /// - Parameters:
    ///   - state: `AppModel.state`; a failure's message was already written by
    ///     `APIError.message(for:)`.
    ///   - email: the signed-in session's email, which `GET /api/me` doesn't return.
    init(profile: UserProfile?, state: AppModel.LoadState, email: String?) {
        if let profile {
            name = profile.displayName
            // A display name is ASCII letters and spaces, so the logo chip's rule fits it.
            initials = LogoImage.initials(for: profile.displayName)
            detail = email
        } else {
            name = "Your account"
            initials = ""
            if case .failed(let message) = state {
                detail = message
            } else {
                detail = email
            }
        }
    }
}

/// The side menu's panel, following the mockup (`Boulder Bay.html`): the app name, the Map /
/// Rankings / Gyms rows with the active one on `Theme.surface`, and the account card at the
/// bottom. Tapping the card opens Sign out above it.
///
/// Only the panel: `AppShell` positions it, dims the screen behind it and animates it.
struct DrawerView: View {
    let activeRoute: AppRoute
    let account: DrawerAccount
    @Binding var isAccountExpanded: Bool
    let onSelect: (AppRoute) -> Void
    /// Shows the "Your places" row. Nil hides it, until the places sheet exists.
    var onShowPlaces: (() -> Void)? = nil
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boulder Bay")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            ForEach(AppRoute.allCases, id: \.self) { route in
                row(
                    title: route.title,
                    symbolName: route.symbolName,
                    isActive: route == activeRoute
                ) {
                    onSelect(route)
                }
            }

            if let onShowPlaces {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                row(title: "Your places", symbolName: "mappin.and.ellipse", isActive: false) {
                    onShowPlaces()
                }
            }

            Spacer(minLength: 16)

            accountCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            UnevenRoundedRectangle(
                bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous
            )
            .fill(Theme.surfaceElevated)
            .shadow(color: Theme.shadow.opacity(0.25), radius: 20, x: 12)
            .ignoresSafeArea()
        }
    }

    private func row(
        title: String,
        symbolName: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                isActive ? Theme.surface : .clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Sign out opens just above the card, as in the mockup. The spacer above takes up the
    /// room, so the rows don't move.
    private var accountCard: some View {
        VStack(spacing: 8) {
            if isAccountExpanded {
                signOutMenu
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            accountButton
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18), value: isAccountExpanded)
    }

    private var accountButton: some View {
        Button {
            isAccountExpanded.toggle()
        } label: {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let detail = account.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isAccountExpanded ? -90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if isAccountExpanded {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.clay, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isAccountExpanded ? "Hides Sign out" : "Shows Sign out")
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.clayTint)
            .frame(width: 42, height: 42)
            .overlay {
                if account.initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17))
                } else {
                    Text(account.initials)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(Theme.clayText)
            .accessibilityHidden(true)
    }

    private var signOutMenu: some View {
        Button(action: onSignOut) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text("Sign out")
                    .font(.system(size: 16))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.danger)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 1, y: 1)
        .shadow(color: Theme.shadow.opacity(0.18), radius: 16, y: 12)
    }
}

#Preview("Drawer") {
    @Previewable @State var expanded = false
    DrawerView(
        activeRoute: .map,
        account: DrawerAccount(name: "Alex Chen", initials: "AC", detail: "alex.chen@example.com"),
        isAccountExpanded: $expanded,
        onSelect: { _ in },
        onShowPlaces: {},
        onSignOut: {}
    )
    .frame(width: 295)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.textPrimary.opacity(0.35))
}
