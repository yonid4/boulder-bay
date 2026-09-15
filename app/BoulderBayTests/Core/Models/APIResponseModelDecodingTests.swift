import Foundation
import Testing

@testable import BoulderBay

struct APIResponseModelDecodingTests {
    @Test func decodesGymDetailWithForecastAndLocalValues() throws {
        let payload = Data(
            """
            {"data": {
                "gym": {
                    "slug": "dogpatch",
                    "name": "Dogpatch Boulders",
                    "brand": "touchstone",
                    "city": "San Francisco",
                    "latitude": 37.7567,
                    "longitude": -122.3903,
                    "logo_url": "http://localhost:8000/api/gyms/dogpatch/logo",
                    "busyness": {
                        "at": "2026-09-13T18:00:00Z",
                        "is_open": true,
                        "busy_pct": 42,
                        "level": "moderate",
                        "source": "live"
                    }
                },
                "address": "2573 3rd St, San Francisco, CA 94107",
                "timezone": "America/Los_Angeles",
                "website_url": "https://touchstoneclimbing.com/dogpatch-boulders/",
                "waiver_url": "https://touchstoneclimbing.com/waiver/",
                "hours": [{
                    "day_of_week": 0,
                    "opens_at": "06:00:00",
                    "closes_at": "18:00:00"
                }],
                "rates": {
                    "day_pass_cents": 3000,
                    "day_pass_peak_cents": 3500,
                    "peak_starts_at": "15:00:00",
                    "monthly_cents": 13000
                },
                "forecast": {
                    "date": "2026-09-13",
                    "timezone": "America/Los_Angeles",
                    "points": [{
                        "starts_at": "2026-09-13T17:00:00Z",
                        "ends_at": "2026-09-13T18:00:00Z",
                        "busy_pct": 31,
                        "level": "quiet"
                    }],
                    "best_time": {
                        "starts_at": "2026-09-13T17:00:00Z",
                        "ends_at": "2026-09-13T18:00:00Z",
                        "busy_pct": 31,
                        "level": "quiet"
                    }
                }
            }}
            """.utf8
        )

        let detail = try APIClient.jsonDecoder
            .decode(APIEnvelope<GymDetail>.self, from: payload)
            .data
        let hours = try #require(detail.hours.first)
        let point = try #require(detail.forecast.points.first)
        let bestTime = try #require(detail.forecast.bestTime)

        #expect(detail.gym.busyness.source == .live)
        #expect(detail.address == "2573 3rd St, San Francisco, CA 94107")
        #expect(detail.websiteUrl?.host() == "touchstoneclimbing.com")
        #expect(detail.waiverUrl?.lastPathComponent == "waiver")
        #expect(hours.dayOfWeek == 0)
        #expect(hours.opensAt == LocalTime(hour: 6, minute: 0, second: 0))
        #expect(hours.closesAt == LocalTime(hour: 18, minute: 0, second: 0))
        #expect(detail.rates.dayPassCents == 3_000)
        #expect(detail.rates.dayPassPeakCents == 3_500)
        #expect(detail.rates.peakStartsAt == LocalTime(hour: 15, minute: 0, second: 0))
        #expect(detail.rates.monthlyCents == 13_000)
        #expect(detail.forecast.date == LocalDate(year: 2026, month: 9, day: 13))
        #expect(point.level == .quiet)
        #expect(bestTime == point)
    }

    @Test func decodesNullableGymDetailFieldsAndForecastGap() throws {
        let payload = Data(
            """
            {"data": {
                "gym": {
                    "slug": "mission",
                    "name": "Mission Cliffs",
                    "brand": "touchstone",
                    "city": "San Francisco",
                    "latitude": 37.7609,
                    "longitude": -122.4128,
                    "logo_url": null,
                    "busyness": {
                        "at": "2026-09-14T05:00:00Z",
                        "is_open": false,
                        "busy_pct": null,
                        "level": null,
                        "source": null
                    }
                },
                "address": null,
                "timezone": "America/Los_Angeles",
                "website_url": null,
                "waiver_url": null,
                "hours": [],
                "rates": {
                    "day_pass_cents": null,
                    "day_pass_peak_cents": null,
                    "peak_starts_at": null,
                    "monthly_cents": null
                },
                "forecast": {
                    "date": "2026-09-13",
                    "timezone": "America/Los_Angeles",
                    "points": [{
                        "starts_at": "2026-09-14T04:00:00Z",
                        "ends_at": "2026-09-14T05:00:00Z",
                        "busy_pct": null,
                        "level": null
                    }],
                    "best_time": null
                }
            }}
            """.utf8
        )

        let detail = try APIClient.jsonDecoder
            .decode(APIEnvelope<GymDetail>.self, from: payload)
            .data

        #expect(detail.gym.logoUrl == nil)
        #expect(detail.gym.busyness.busyPct == nil)
        #expect(detail.address == nil)
        #expect(detail.websiteUrl == nil)
        #expect(detail.waiverUrl == nil)
        #expect(detail.rates.dayPassCents == nil)
        #expect(detail.rates.dayPassPeakCents == nil)
        #expect(detail.rates.peakStartsAt == nil)
        #expect(detail.rates.monthlyCents == nil)
        #expect(detail.forecast.points[0].busyPct == nil)
        #expect(detail.forecast.points[0].level == nil)
        #expect(detail.forecast.bestTime == nil)
    }

    @Test func decodesRankingsWithSavedLocationAndNestedGym() throws {
        let payload = Data(
            """
            {"data": {
                "at": "2026-09-13T18:00:00Z",
                "locations": [{
                    "location": {
                        "id": "d16878be-c4bc-462f-8929-c464b6a5efad",
                        "label": "Home",
                        "address": "Redwood City, CA",
                        "latitude": 37.4852,
                        "longitude": -122.2364,
                        "is_default": true
                    },
                    "ranked_gyms": [{
                        "rank": 1,
                        "score": 72.4,
                        "travel_minutes": 14.2,
                        "is_member": true,
                        "gym": {
                            "slug": "dogpatch",
                            "name": "Dogpatch Boulders",
                            "brand": "touchstone",
                            "city": "San Francisco",
                            "latitude": 37.7567,
                            "longitude": -122.3903,
                            "logo_url": null,
                            "busyness": {
                                "at": "2026-09-13T18:00:00Z",
                                "is_open": true,
                                "busy_pct": 70,
                                "level": "packed",
                                "source": "forecast"
                            }
                        }
                    }]
                }]
            }}
            """.utf8
        )

        let rankings = try APIClient.jsonDecoder
            .decode(APIEnvelope<Rankings>.self, from: payload)
            .data
        let locationRankings = try #require(rankings.locations.first)
        let rankedGym = try #require(locationRankings.rankedGyms.first)

        #expect(locationRankings.location.id == UUID(uuidString: "d16878be-c4bc-462f-8929-c464b6a5efad"))
        #expect(locationRankings.location.label == "Home")
        #expect(locationRankings.location.isDefault)
        #expect(rankedGym.rank == 1)
        #expect(rankedGym.score == 72.4)
        #expect(rankedGym.travelMinutes == 14.2)
        #expect(rankedGym.isMember)
        #expect(rankedGym.gym.id == "dogpatch")
    }

    @Test func decodesProfileWithNullableDisplayName() throws {
        let payload = Data(
            """
            {"data": {
                "id": "7878e808-a48f-4649-8a65-3feb6029a591",
                "display_name": null
            }}
            """.utf8
        )

        let profile = try APIClient.jsonDecoder
            .decode(APIEnvelope<UserProfile>.self, from: payload)
            .data

        #expect(profile.id == UUID(uuidString: "7878e808-a48f-4649-8a65-3feb6029a591"))
        #expect(profile.displayName == nil)
    }
}
