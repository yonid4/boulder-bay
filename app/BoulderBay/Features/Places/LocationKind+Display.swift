import Foundation

/// How a place's kind looks in the form, the places sheet and the switcher (design §9).
extension LocationKind {
    var title: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .other: "mappin"
        }
    }

    /// The label a new place of this kind starts with; `other` starts blank.
    var defaultLabel: String {
        switch self {
        case .home: "Home"
        case .work: "Work"
        case .other: ""
        }
    }
}
