from fastapi.testclient import TestClient


def test_health_returns_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_gyms_returns_seed_list(client: TestClient) -> None:
    response = client.get("/api/gyms")
    assert response.status_code == 200
    gyms = response.json()["data"]
    assert gyms, "expected at least one gym"
    assert {"id", "name", "brand", "city", "lat", "lng"} <= set(gyms[0])
