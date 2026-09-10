import Foundation

/// The sixteen gyms and their hours, transcribed verbatim from the seed migrations
/// `b00fd69a53b6` (gyms + `gym_hours`) and `92a96b89e01d` (the gym → logo mapping).
/// This is the mock's reference data; the backend is the source of truth and this copy
/// must be corrected there first, never here alone. The twelve marks in `Logos/` are
/// copies of the migration's seed PNGs for the same reason: the mock stands in for the
/// backend, so it has to serve the bytes the backend will serve from `gym_logos`.
enum SeedData {
    struct SeedGym: Sendable {
        let slug: String
        let name: String
        let brand: Brand
        let city: String
        let latitude: Double
        let longitude: Double
        let address: String
        let websiteURL: String
        let waiverURL: String
        let dayPassCents: Int
        let dayPassPeakCents: Int?
        let peakStartsAt: ClockTime?
        let monthlyCents: Int
        /// `gym_logos.key` — ten per-gym marks plus `movement` and `benchmark`.
        let logoKey: String
    }

    /// Opening hours by weekday, `0 = Sunday`, as `(opens, closes)` whole hours.
    typealias Week = [(Int, Int)]

    private static let touchstonePeak = ClockTime(hour: 15)

    static let gyms: [SeedGym] = [
        // Touchstone: $30 before 3pm, $35 after.
        SeedGym(
            slug: "mission", name: "Mission Cliffs", brand: .touchstone, city: "San Francisco",
            latitude: 37.7609801, longitude: -122.4150888,
            address: "2295 Harrison St, San Francisco, CA 94110",
            websiteURL: "https://touchstoneclimbing.com/mission-cliffs/",
            waiverURL: "https://touchstone.rphq.com/missioncliffs/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "mission"
        ),
        SeedGym(
            slug: "dogpatch", name: "Dogpatch Boulders", brand: .touchstone, city: "San Francisco",
            latitude: 37.7567054, longitude: -122.3903193,
            address: "2573 3rd St, San Francisco, CA 94107",
            websiteURL: "https://touchstoneclimbing.com/dogpatch-boulders/",
            waiverURL: "https://touchstone.rphq.com/dogpatch/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "dogpatch"
        ),
        SeedGym(
            slug: "hyperion", name: "Hyperion Climbing", brand: .touchstone, city: "Redwood City",
            latitude: 37.4842893, longitude: -122.217014,
            address: "801 Willow St, Redwood City, CA 94063",
            websiteURL: "https://touchstoneclimbing.com/hyperion/",
            waiverURL: "https://portal.touchstoneclimbing.com/hyperion/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "hyperion"
        ),
        SeedGym(
            slug: "gwpc", name: "Great Western Power Company", brand: .touchstone, city: "Oakland",
            latitude: 37.8098428, longitude: -122.2727291,
            address: "520 20th St, Oakland, CA 94612",
            websiteURL: "https://touchstoneclimbing.com/gwpower-co/",
            waiverURL: "https://touchstone.rphq.com/power/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "gwpc"
        ),
        SeedGym(
            slug: "pipe", name: "Pacific Pipe", brand: .touchstone, city: "Oakland",
            latitude: 37.8156325, longitude: -122.2913122,
            address: "2140 Mandela Pkwy, Oakland, CA 94607",
            websiteURL: "https://touchstoneclimbing.com/pacific-pipe/",
            waiverURL: "https://touchstone.rphq.com/pacificpipe/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "pipe"
        ),
        SeedGym(
            slug: "ironworks", name: "Berkeley Ironworks", brand: .touchstone, city: "Berkeley",
            latitude: 37.8509776, longitude: -122.2951509,
            address: "800 Potter St, Berkeley, CA 94710",
            websiteURL: "https://touchstoneclimbing.com/ironworks/",
            waiverURL: "https://touchstone.rphq.com/ironworks/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "ironworks"
        ),
        SeedGym(
            slug: "the-oaks", name: "The Oaks Climbing", brand: .touchstone, city: "Berkeley",
            latitude: 37.8915899, longitude: -122.2806575,
            address: "1875 Solano Ave, Berkeley, CA 94707",
            websiteURL: "https://touchstoneclimbing.com/the-oaks/",
            waiverURL: "https://portal.touchstoneclimbing.com/oaks/agreements/waiver",
            dayPassCents: 3000, dayPassPeakCents: 3500, peakStartsAt: touchstonePeak,
            monthlyCents: 13000, logoKey: "the-oaks"
        ),
        // The Studio is Touchstone but cheaper: $25 before 3pm, $30 after.
        SeedGym(
            slug: "studio", name: "The Studio Climbing", brand: .touchstone, city: "San Jose",
            latitude: 37.330216, longitude: -121.8885325,
            address: "396 S 1st St, San Jose, CA 95113",
            websiteURL: "https://portal.touchstoneclimbing.com/studio",
            waiverURL: "https://portal.touchstoneclimbing.com/studio/agreements/waiver",
            dayPassCents: 2500, dayPassPeakCents: 3000, peakStartsAt: touchstonePeak,
            monthlyCents: 11200, logoKey: "studio"
        ),

        // Movement: flat day rate, monthly varies by location. One shared mark.
        SeedGym(
            slug: "mv-sf", name: "Movement San Francisco", brand: .movement, city: "San Francisco",
            latitude: 37.8041752, longitude: -122.4707639,
            address: "924 Mason St, San Francisco, CA 94129",
            websiteURL: "https://movementgyms.com/san-francisco/",
            waiverURL: "https://portal.movementgyms.com/san-francisco/agreements/participant-agreement",
            dayPassCents: 3300, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 11500, logoKey: "movement"
        ),
        SeedGym(
            slug: "mv-belmont", name: "Movement Belmont", brand: .movement, city: "Belmont",
            latitude: 37.5289862, longitude: -122.2900729,
            address: "100 El Camino Real, Belmont, CA 94002",
            websiteURL: "https://movementgyms.com/belmont/",
            waiverURL: "https://portal.movementgyms.com/belmont/agreements/participant-agreement",
            dayPassCents: 3300, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 11400, logoKey: "movement"
        ),
        SeedGym(
            slug: "mv-mountain-view", name: "Movement Mountain View", brand: .movement,
            city: "Mountain View",
            latitude: 37.4028887, longitude: -122.1163429,
            address: "630 San Antonio Rd, Mountain View, CA 94040",
            websiteURL: "https://movementgyms.com/mountain-view",
            waiverURL: "https://portal.movementgyms.com/mountain-view/agreements/participant-agreement",
            dayPassCents: 3300, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 12100, logoKey: "movement"
        ),
        SeedGym(
            slug: "mv-santa-clara", name: "Movement Santa Clara", brand: .movement,
            city: "Santa Clara",
            latitude: 37.3667359, longitude: -121.9505707,
            address: "801 Martin Ave, Santa Clara, CA 95050",
            websiteURL: "https://movementgyms.com/santa-clara/",
            waiverURL: "https://portal.movementgyms.com/santa-clara/agreements/participant-agreement",
            dayPassCents: 3300, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 12100, logoKey: "movement"
        ),

        // Benchmark: two locations, one website, one waiver portal, one shared mark.
        SeedGym(
            slug: "bm-sf", name: "Benchmark San Francisco", brand: .benchmark, city: "San Francisco",
            latitude: 37.7888786, longitude: -122.4242155,
            address: "1414 Van Ness Ave, San Francisco, CA 94109",
            websiteURL: "https://www.benchmarkclimbing.com/",
            waiverURL: "https://benchmark.portal.approach.app/profile/sign-waiver",
            dayPassCents: 3000, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 9900, logoKey: "benchmark"
        ),
        SeedGym(
            slug: "bm-berkeley", name: "Benchmark Berkeley", brand: .benchmark, city: "Berkeley",
            latitude: 37.8781104, longitude: -122.2712743,
            address: "1607 Shattuck Ave., Berkeley, CA 94709",
            websiteURL: "https://www.benchmarkclimbing.com/",
            waiverURL: "https://benchmark.portal.approach.app/profile/sign-waiver",
            dayPassCents: 3000, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 9900, logoKey: "benchmark"
        ),

        // Independents.
        SeedGym(
            slug: "the-peak", name: "The Peak of Fremont", brand: .independent, city: "Fremont",
            latitude: 37.5105982, longitude: -121.9535299,
            address: "4020 Technology Pl Suite 1, Fremont, CA 94538",
            websiteURL: "https://thepeakoffremont.com/",
            waiverURL: "https://thepeakoffremont.com/the-peak-of-fremont-waiver/",
            dayPassCents: 3000, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 7200, logoKey: "the-peak"
        ),
        SeedGym(
            slug: "mosaic", name: "Mosaic Boulders", brand: .independent, city: "Berkeley",
            latitude: 37.8674946, longitude: -122.2613914,
            address: "2369 Telegraph Ave, Berkeley, CA 94704",
            websiteURL: "https://www.mosaicboulders.com/",
            waiverURL: "https://mosaic.portal.approach.app/waiver",
            dayPassCents: 2200, dayPassPeakCents: nil, peakStartsAt: nil,
            monthlyCents: 7500, logoKey: "mosaic"
        ),
    ]

    /// The 112 `gym_hours` rows, keyed by slug, Sunday first. No house pattern holds
    /// (Dogpatch and Pacific Pipe run later on Tue/Thu; Movement closes earlier on
    /// Sunday than Saturday; Mosaic opens at 13:00 on weekdays), so each week is spelled
    /// out rather than generated.
    static let hours: [String: Week] = [
        "bm-sf": [(10, 19), (11, 22), (11, 22), (11, 22), (11, 22), (11, 22), (10, 19)],
        "bm-berkeley": [(10, 19), (7, 22), (7, 22), (7, 22), (7, 22), (7, 22), (10, 19)],
        "mission": [(9, 19), (6, 22), (6, 22), (6, 22), (6, 22), (6, 22), (9, 19)],
        "dogpatch": [(10, 19), (7, 22), (7, 23), (7, 22), (7, 23), (7, 22), (10, 19)],
        "mv-sf": [(8, 18), (6, 23), (6, 23), (6, 23), (6, 23), (6, 23), (8, 20)],
        "mv-belmont": [(8, 18), (6, 23), (6, 23), (6, 23), (6, 23), (6, 23), (8, 20)],
        "hyperion": [(10, 18), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (10, 18)],
        "mv-mountain-view": [(8, 18), (6, 23), (6, 23), (6, 23), (6, 23), (6, 23), (8, 20)],
        "mv-santa-clara": [(8, 18), (6, 23), (6, 23), (6, 23), (6, 23), (6, 23), (8, 20)],
        "studio": [(10, 17), (10, 22), (10, 22), (10, 22), (10, 22), (10, 22), (10, 17)],
        "the-peak": [(10, 18), (12, 22), (12, 22), (12, 22), (12, 22), (12, 22), (10, 18)],
        "gwpc": [(9, 16), (6, 22), (6, 22), (6, 22), (6, 22), (6, 22), (9, 16)],
        "pipe": [(10, 19), (7, 22), (7, 23), (7, 22), (7, 23), (7, 22), (10, 19)],
        "ironworks": [(10, 19), (6, 22), (6, 22), (6, 22), (6, 22), (6, 22), (10, 19)],
        "the-oaks": [(10, 17), (8, 22), (8, 22), (8, 22), (8, 22), (8, 22), (10, 17)],
        "mosaic": [(11, 23), (13, 23), (13, 23), (13, 23), (13, 23), (13, 23), (11, 23)],
    ]

    static func gym(slug: String) -> SeedGym? {
        gyms.first { $0.slug == slug }
    }

    /// The bundled copy of a `gym_logos` row, as the `logo_url` the mock hands out.
    /// `AsyncImage` loads `file://` URLs like any other, so `GymLogoView` needs no
    /// mock-specific path. `nil` only if the resource is missing from the bundle.
    static func logoURL(key: String) -> URL? {
        Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Logos")
    }

    /// All seven `GymHours` rows for a gym.
    static func weekHours(slug: String) -> [GymHours] {
        (hours[slug] ?? []).enumerated().map { day, span in
            GymHours(dayOfWeek: day, opensAt: ClockTime(hour: span.0), closesAt: ClockTime(hour: span.1))
        }
    }

    static func hours(slug: String, dayOfWeek: Int) -> HoursRange? {
        guard let week = hours[slug], week.indices.contains(dayOfWeek) else { return nil }
        let span = week[dayOfWeek]
        return HoursRange(opensAt: ClockTime(hour: span.0), closesAt: ClockTime(hour: span.1))
    }
}
