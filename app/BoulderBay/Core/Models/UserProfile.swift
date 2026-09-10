import Foundation

/// `GET /api/me`. The backend upserts the `profiles` row on first call; `email` comes
/// from the verified JWT.
struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let email: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
    }
}
