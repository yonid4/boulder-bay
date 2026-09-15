import Foundation

struct SavedLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let isDefault: Bool
}
