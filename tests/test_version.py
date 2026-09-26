from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_version() -> None:
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"version": "0.1.0"}
