from fastapi import FastAPI

app = FastAPI(title="Boulder Bay")

MOCK_GYMS = [
    {
        "id": "dogpatch",
        "name": "Dogpatch Boulders",
        "brand": "Touchstone",
        "city": "SF",
        "lat": 37.7565,
        "lng": -122.3881,
        "rates": {"day": 30, "month": 95},
        "live": {"busy_pct": 54, "level": "Moderate"},
    },
    {
        "id": "mv-belmont",
        "name": "Movement Belmont",
        "brand": "Movement",
        "city": "Belmont",
        "lat": 37.5221,
        "lng": -122.2761,
        "rates": {"day": 32, "month": 109},
        "live": {"busy_pct": 23, "level": "Quiet"},
    },
    {
        "id": "bridges",
        "name": "Bridges Rock Gym",
        "brand": "Independent",
        "city": "El Cerrito",
        "lat": 37.9162,
        "lng": -122.3051,
        "rates": {"day": 25, "month": 79},
        "live": {"busy_pct": 12, "level": "Quiet"},
    },
    # Remaining 6 gyms omitted for brevity
]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/gyms")
def get_gyms() -> dict[str, list[dict[str, object]]]:
    return {"data": MOCK_GYMS}
