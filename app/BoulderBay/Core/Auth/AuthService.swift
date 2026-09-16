import Foundation
import Supabase

enum SignUpResult: Equatable, Sendable {
    case signedIn
    case confirmationRequired
}

enum AuthServiceError: Error, Equatable {
    case invalidDisplayName
}

@MainActor
@Observable
final class AuthService {
    private let client: SupabaseClient
    @ObservationIgnored
    nonisolated(unsafe) private var authStateTask: Task<Void, Never>?

    private(set) var session: Session?
    private(set) var isRestoringSession = true

    init(client: SupabaseClient) {
        self.client = client

        authStateTask = Task { [weak self, authStateChanges = client.auth.authStateChanges] in
            for await (_, session) in authStateChanges {
                guard let self else { return }
                self.session = session
                self.isRestoringSession = false
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signIn(email: String, password: String) async throws {
        session = try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String) async throws -> SignUpResult {
        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsOnlyASCIINameCharacters = displayName.unicodeScalars.allSatisfy {
            $0.value == 0x20 || (0x41...0x5A).contains($0.value)
                || (0x61...0x7A).contains($0.value)
        }
        guard
            (1...80).contains(displayName.unicodeScalars.count),
            containsOnlyASCIINameCharacters
        else {
            throw AuthServiceError.invalidDisplayName
        }

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )

        if let session = response.session {
            self.session = session
            return .signedIn
        }
        return .confirmationRequired
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
        session = nil
    }

    func accessToken() async throws -> String {
        try await client.auth.session.accessToken
    }
}
