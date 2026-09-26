import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_regular_commission() -> None:
    response = client.get("/commission", params={"price": 5_000_000})
    assert response.status_code == 200
    assert response.json() == {"commission": 150_000, "percent": 3, "price": 5_000_000}


def test_min_commission_applied() -> None:
    response = client.get("/commission", params={"price": 1_000_000})
    assert response.status_code == 200
    assert response.json()["commission"] == 50_000


def test_custom_min_commission() -> None:
    params = {"price": 1_000_000, "min_commission": 0}
    assert client.get("/commission", params=params).json()["commission"] == 30_000


def test_custom_percent() -> None:
    response = client.get("/commission", params={"price": 5_000_000, "percent": 2.5})
    assert response.status_code == 200
    assert response.json() == {"commission": 125_000, "percent": 2.5, "price": 5_000_000}


def test_max_percent_is_allowed() -> None:
    params = {"price": 1_000_000, "percent": 20}
    assert client.get("/commission", params=params).json()["commission"] == 200_000


@pytest.mark.parametrize(
    "params",
    [
        {"price": 0},
        {"price": -1},
        {"price": 1_000_000, "percent": 0},
        {"price": 1_000_000, "percent": -1},
        {"price": 1_000_000, "percent": 20.1},
        {"price": 1_000_000, "min_commission": -1},
        {},
    ],
    ids=[
        "price-zero",
        "price-negative",
        "percent-zero",
        "percent-negative",
        "percent-above-20",
        "min-commission-negative",
        "price-missing",
    ],
)
def test_invalid_params_return_422(params: dict[str, float]) -> None:
    assert client.get("/commission", params=params).status_code == 422
