import Foundation
import Observation

/// Everything the detail screen shows for one gym, derived from `GymDetail` plus the
/// ranking entry (travel, distance, membership) and the scrubber's hour.
@MainActor
@Observable
final class GymDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// One bar of the hourly chart.
    struct Bar: Identifiable, Hashable {
        let hour: Int
        let busyPct: Int
        let isCurrent: Bool
        let isPast: Bool

        var id: Int { hour }
        var level: BusynessLevel { BusynessLevel(percent: busyPct) }
        /// Past hours fade, the current hour is solid, the future slightly lighter.
        var opacity: Double { isPast ? 0.3 : isCurrent ? 1 : 0.8 }
    }

    let slug: String
    private(set) var detail: GymDetail?
    private(set) var state: State = .loading

    private let service: GymDetailService
    private let rankings: RankingStore
    private let memberships: MembershipStore
    private let locations: LocationStore
    private let now: @Sendable () -> Date

    init(
        slug: String, service: GymDetailService, rankings: RankingStore,
        memberships: MembershipStore, locations: LocationStore,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.slug = slug
        self.service = service
        self.rankings = rankings
        self.memberships = memberships
        self.locations = locations
        self.now = now
    }

    func load() async {
        state = .loading
        do {
            detail = try await service.detail(slug: slug)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Time

    var isPlanning: Bool { rankings.isPlanning }
    var effectiveHour: Int { rankings.effectiveHour }
    var nowLabel: String { isPlanning ? "At \(Format.hour(effectiveHour))" : "Right now" }

    // MARK: Busyness

    var gym: Gym? { detail?.gym }
    var isMember: Bool { memberships.isMember(slug) }
    var entry: RankingEntry? { rankings.entry(for: slug) }
    var hoursToday: HoursRange? { detail?.gym.hoursToday }
    var isOpen: Bool { hoursToday?.contains(ClockTime(hour: effectiveHour)) ?? false }

    /// Live for "now", the curve for a planned hour; nil when closed or unknown.
    var busyPct: Int? {
        guard let detail, isOpen else { return nil }
        if isPlanning {
            return BusynessForecast.busyPct(in: detail.forecast, at: effectiveHour)
        }
        return detail.gym.live?.busyPct ?? BusynessForecast.busyPct(in: detail.forecast, at: effectiveHour)
    }

    var level: BusynessLevel? { busyPct.map(BusynessLevel.init(percent:)) }
    var capacityText: String { busyPct.map { "\($0)% of capacity" } ?? "No live reading" }

    var bestWindow: ForecastPoint? {
        detail.flatMap { BusynessForecast.bestWindow(in: $0.forecast, after: effectiveHour) }
    }

    /// "7 PM – 8 PM", or "Closes soon" / "Closed today" when no open hour remains.
    var bestTimeText: String {
        if let bestWindow { return Format.window(startingAt: bestWindow.hour) }
        return hoursToday == nil ? "Closed today" : "Closes soon"
    }

    /// "quiet, about 22%", or the current reading when nothing is left today.
    var bestNoteText: String {
        if let bestWindow {
            return "\(bestWindow.level.label.lowercased()), about \(bestWindow.busyPct)%"
        }
        if let busyPct { return "\(busyPct)% \(isPlanning ? "at \(Format.hour(effectiveHour))" : "now")" }
        return "Try tomorrow"
    }

    /// One bar per open hour today, the current hour replaced by the live reading.
    var bars: [Bar] {
        guard let detail, let hours = hoursToday else { return [] }
        let byHour = Dictionary(detail.forecast.map { ($0.hour, $0.busyPct) }, uniquingKeysWith: { a, _ in a })
        return hours.openHours.compactMap { hour in
            let isCurrent = hour == effectiveHour
            let pct = isCurrent ? (busyPct ?? byHour[hour]) : byHour[hour]
            guard let pct else { return nil }
            return Bar(hour: hour, busyPct: pct, isCurrent: isCurrent, isPast: hour < effectiveHour)
        }
    }

    /// Every fourth open hour plus the last, as the mockup labels the axis.
    var ticks: [Int] {
        guard let hours = hoursToday?.openHours, let last = hours.last else { return [] }
        return hours.enumerated().compactMap { index, hour in
            index % 4 == 0 || hour == last ? hour : nil
        }
    }

    // MARK: Info rows

    var hoursText: String { hoursToday.map(Format.hoursRange) ?? "Closed today" }
    var openStatusText: String { Format.openStatus(hoursToday: hoursToday, at: effectiveHour) }

    var travelText: String? {
        guard let entry, let location = locations.current else { return nil }
        return "\(entry.travelMinutes) min from \(location.label)"
    }

    var distanceText: String? { entry.map { Format.miles($0.distanceMiles) } }

    var dayPassText: String? { gym?.rates.dayPassCents.map(Format.dollars(cents:)) }
    var monthlyText: String? { gym?.rates.monthlyCents.map(Format.dollars(cents:)) }

    /// "$35 after 3 PM" for tiered gyms; the brand's network otherwise.
    var rateNote: String? {
        guard let gym else { return nil }
        if let peak = gym.rates.dayPassPeakCents, let starts = gym.rates.peakStartsAt {
            return "Day pass \(Format.dollars(cents: peak)) after \(Format.clockTime(starts))"
        }
        return gym.brand == .independent ? "Independent gym" : "Part of the \(gym.brand.displayName) network"
    }

    var hasWaiver: Bool { gym?.waiverURL != nil }
}
