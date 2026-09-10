/// The four values `gyms.brand` allows. The API sends the lowercase form.
enum Brand: String, Codable, Hashable, Sendable, CaseIterable {
    case touchstone
    case movement
    case benchmark
    case independent

    var displayName: String {
        switch self {
        case .touchstone: "Touchstone"
        case .movement: "Movement"
        case .benchmark: "Benchmark"
        case .independent: "Independent"
        }
    }
}
