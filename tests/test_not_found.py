from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_unknown_path_returns_404() -> None:
    response = client.get("/does-not-exist")
    assert response.status_code == 404


def test_health_post_returns_405() -> None:
    response = client.post("/health")
    assert response.status_code == 405
