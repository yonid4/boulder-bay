import Foundation

/// At most one home and one work place per user; any number of `other`.
enum LocationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case home
    case work
    case other
}

struct SavedLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let isDefault: Bool
    let kind: LocationKind
}

/// Body of `POST /api/me/locations`. The backend rejects unknown fields with a 422.
struct CreateSavedLocation: Encodable, Hashable, Sendable {
    var label: String
    var kind: LocationKind
    var address: String?
    var latitude: Double
    var longitude: Double
    var makeDefault: Bool = false
}

/// Body of `PATCH /api/me/locations/{id}`: only the fields that are set are sent.
struct UpdateSavedLocation: Encodable, Hashable, Sendable {
    var label: String?
    var kind: LocationKind?
    /// `nil` leaves the address alone; `.some(nil)` clears it (sent as an explicit `null`).
    var address: String??
    var latitude: Double?
    var longitude: Double?
    /// `true` promotes this place to the default. There is no way to un-default a place.
    var makeDefault: Bool?

    init(
        label: String? = nil,
        kind: LocationKind? = nil,
        address: String?? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        makeDefault: Bool? = nil
    ) {
        self.label = label
        self.kind = kind
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.makeDefault = makeDefault
    }

    private enum CodingKeys: String, CodingKey {
        case label, kind, address, latitude, longitude, makeDefault
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(kind, forKey: .kind)
        if let address {
            try container.encode(address, forKey: .address)
        }
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(makeDefault, forKey: .makeDefault)
    }
}
