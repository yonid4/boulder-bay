import Foundation

/// Stands in for Supabase when the project has no keys, and in previews and tests.
/// Any email with a six-character password signs in; the "account" is remembered in
/// `UserDefaults` so a relaunch stays signed in, like the real keychain-backed session.
@MainActor
final class MockAuthService: AuthService {
    static let persistenceKey = "BBMockAuthUser"
    static let minimumPasswordLength = 6

    let session: AuthSession
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, initialState: AuthState? = nil) {
        self.defaults = defaults
        session = AuthSession(state: initialState ?? .resolving)
    }

    /// A service already signed in as `user` — what previews want.
    static func signedIn(as user: AuthUser = .preview) -> MockAuthService {
        MockAuthService(defaults: UserDefaults(suiteName: "BBMockAuthPreview")!, initialState: .signedIn(user))
    }

    func start() async {
        guard case .resolving = session.state else { return }
        if let data = defaults.data(forKey: Self.persistenceKey),
           let stored = try? JSONDecoder().decode(StoredUser.self, from: data)
        {
            session.transition(to: .signedIn(stored.user))
        } else {
            session.transition(to: .signedOut)
        }
    }

    func signIn(email: String, password: String) async throws {
        let email = Self.normalize(email)
        guard Self.looksLikeEmail(email), password.count >= Self.minimumPasswordLength else {
            throw AuthServiceError.invalidCredentials
        }
        let user = AuthUser(
            id: Self.stableID(for: email), email: email, displayName: Self.displayName(for: email)
        )
        persist(user)
        session.transition(to: .signedIn(user))
    }

    func signUp(name: String, email: String, password: String) async throws {
        let email = Self.normalize(email)
        guard Self.looksLikeEmail(email) else { throw AuthServiceError.invalidCredentials }
        guard password.count >= Self.minimumPasswordLength else {
            throw AuthServiceError.weakPassword(
                "Password should be at least \(Self.minimumPasswordLength) characters."
            )
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var user = AuthUser(
            id: Self.stableID(for: email), email: email,
            displayName: trimmed.isEmpty ? nil : trimmed
        )
        user.isNewAccount = true
        persist(user)
        session.transition(to: .signedIn(user))
    }

    func signOut() async throws {
        defaults.removeObject(forKey: Self.persistenceKey)
        session.transition(to: .signedOut)
    }

    func accessToken() async -> String? {
        session.isSignedIn ? "mock-access-token" : nil
    }

    // MARK: Helpers

    private struct StoredUser: Codable {
        let id: UUID
        let email: String
        let displayName: String?

        var user: AuthUser { AuthUser(id: id, email: email, displayName: displayName) }
    }

    private func persist(_ user: AuthUser) {
        let stored = StoredUser(id: user.id, email: user.email, displayName: user.displayName)
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.persistenceKey)
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func looksLikeEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    /// The same email always yields the same id, so a mock sign-out/sign-in round trip
    /// looks like the same account.
    private static func stableID(for email: String) -> UUID {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in email.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(format: "%016llx", hash)
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(12).prefix(3))-8\(hex.prefix(3))-\(hex.suffix(12))")!
    }

    /// "alex.chen@…" → "Alex Chen", so the side menu has something to show.
    private static func displayName(for email: String) -> String? {
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        let words = local.split(whereSeparator: { ".-_".contains($0) })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

extension AuthUser {
    static let preview = AuthUser(
        id: UUID(uuidString: "0b6d1c8a-1e2f-4a3b-9c4d-5e6f7a8b9c0d")!,
        email: "alex.chen@example.com",
        displayName: "Alex Chen"
    )
}
