import Foundation

struct UserProfile: Codable, Hashable, Sendable {
    let id: UUID
    let displayName: String?
}
