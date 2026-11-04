import Foundation

/// The Gyms screen's lists, as pure functions of the gym list, the membership set and the query.
enum GymList {
    /// The gyms the user belongs to, in list order. Follows `AppModel.memberships`, never
    /// `Gym.isMember`, which is only as fresh as the last gym load.
    static func members(of gyms: [Gym], memberships: Set<String>) -> [Gym] {
        gyms.filter { memberships.contains($0.slug) }
    }

    /// The gyms the user doesn't belong to, in list order: what a search offers before anything
    /// is typed.
    static func notJoined(in gyms: [Gym], memberships: Set<String>) -> [Gym] {
        gyms.filter { !memberships.contains($0.slug) }
    }

    /// The gyms matching `query` across name, city and brand, in list order, ignoring case and
    /// surrounding spaces. A blank query is no search, so it matches nothing.
    static func results(in gyms: [Gym], query: String) -> [Gym] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return gyms.filter {
            "\($0.name) \($0.city) \(brandLabel(for: $0))".lowercased().contains(query)
        }
    }

    /// "None yet", "1 gym", "2 gyms", beside the "Your gyms" heading.
    static func memberCountLabel(_ count: Int) -> String {
        switch count {
        case 0: "None yet"
        case 1: "1 gym"
        default: "\(count) gyms"
        }
    }

    /// The brand as a row shows it and a search matches it: "Touchstone".
    static func brandLabel(for gym: Gym) -> String {
        gym.brand.rawValue.capitalized
    }
}
