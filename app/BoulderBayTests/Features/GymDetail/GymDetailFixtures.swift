import Foundation

@testable import BoulderBay

/// A Sunday in September, with the gym's local day the same as the forecast's.
enum GymDetailFixtures {
    /// 2026-09-13 18:00 UTC, which is 11 AM in Los Angeles.
    static let at = Date(timeIntervalSince1970: 1_789_322_400)
    /// 2026-09-13, a Sunday.
    static let sunday = LocalDate(year: 2026, month: 9, day: 13)!

    /// The realistic `{"data": GymDetail}` the API returns for a fully populated gym.
    static let fullPayload = Data(
        """
        {"data": {
            "gym": {
                "slug": "dogpatch",
                "name": "Dogpatch Boulders",
                "brand": "touchstone",
                "city": "San Francisco",
                "latitude": 37.7567,
                "longitude": -122.3903,
                "logo_url": "https://api.test/api/gyms/dogpatch/logo",
                "is_member": true,
                "busyness": {
                    "at": "2026-09-13T18:00:00+00:00",
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
            "hours": [
                {"day_of_week": 0, "opens_at": "08:00:00", "closes_at": "20:00:00"},
                {"day_of_week": 1, "opens_at": "06:00:00", "closes_at": "23:00:00"},
                {"day_of_week": 2, "opens_at": "06:00:00", "closes_at": "23:00:00"},
                {"day_of_week": 3, "opens_at": "06:00:00", "closes_at": "23:00:00"},
                {"day_of_week": 4, "opens_at": "06:00:00", "closes_at": "23:00:00"},
                {"day_of_week": 5, "opens_at": "06:00:00", "closes_at": "22:30:00"},
                {"day_of_week": 6, "opens_at": "08:00:00", "closes_at": "20:00:00"}
            ],
            "rates": {
                "day_pass_cents": 3000,
                "day_pass_peak_cents": 3500,
                "peak_starts_at": "15:00:00",
                "monthly_cents": 13000
            },
            "forecast": {
                "date": "2026-09-13",
                "timezone": "America/Los_Angeles",
                "points": [
                    {
                        "starts_at": "2026-09-13T17:00:00+00:00",
                        "ends_at": "2026-09-13T18:00:00+00:00",
                        "busy_pct": 31,
                        "level": "quiet",
                        "source": "observed"
                    },
                    {
                        "starts_at": "2026-09-13T18:00:00+00:00",
                        "ends_at": "2026-09-13T19:00:00+00:00",
                        "busy_pct": 42,
                        "level": "moderate",
                        "source": "live"
                    },
                    {
                        "starts_at": "2026-09-13T19:00:00+00:00",
                        "ends_at": "2026-09-13T20:00:00+00:00",
                        "busy_pct": null,
                        "level": null,
                        "source": null
                    }
                ],
                "best_time": null
            }
        }}
        """.utf8
    )

    /// What the API returns for a gym with every nullable field null and no hours.
    static let sparsePayload = Data(
        """
        {"data": {
            "gym": {
                "slug": "bm-berkeley",
                "name": "Benchmark Berkeley",
                "brand": "benchmark",
                "city": "Berkeley",
                "latitude": 37.8716,
                "longitude": -122.2727,
                "logo_url": null,
                "is_member": false,
                "busyness": {
                    "at": "2026-09-13T18:00:00+00:00",
                    "is_open": true,
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
                "points": [],
                "best_time": null
            }
        }}
        """.utf8
    )

    static var full: GymDetail { decode(fullPayload) }
    static var sparse: GymDetail { decode(sparsePayload) }

    /// `full` with a best time later in the day: 4 PM to 5 PM in Los Angeles.
    static var fullWithBestTime: GymDetail {
        let bestTime = """
            "best_time": {
                "starts_at": "2026-09-13T23:00:00+00:00",
                "ends_at": "2026-09-14T00:00:00+00:00",
                "busy_pct": 28,
                "level": "quiet",
                "source": "forecast"
            }
            """
        let payload = String(decoding: fullPayload, as: UTF8.self)
            .replacingOccurrences(of: "\"best_time\": null", with: bestTime)
        return decode(Data(payload.utf8))
    }

    /// A forecast for the fixture day, for the format tests to choose its points.
    static func forecast(
        points: [ForecastPoint], bestTime: ForecastPoint? = nil
    ) -> BusynessForecast {
        BusynessForecast(
            date: sunday, timezone: "America/Los_Angeles", points: points, bestTime: bestTime
        )
    }

    /// One hour starting `hoursAfterAt` hours after `at`.
    static func point(
        hoursAfterAt: Int,
        percent: Int? = 30,
        level: BusynessLevel? = .quiet,
        source: BusynessSource? = .forecast
    ) -> ForecastPoint {
        let start = at.addingTimeInterval(TimeInterval(hoursAfterAt) * 3600)
        return ForecastPoint(
            startsAt: start,
            endsAt: start.addingTimeInterval(3600),
            busyPct: percent,
            level: level,
            source: source
        )
    }

    private static func decode(_ payload: Data) -> GymDetail {
        // A broken fixture is a programmer error in the test itself.
        try! APIClient.jsonDecoder.decode(APIEnvelope<GymDetail>.self, from: payload).data
    }
}
