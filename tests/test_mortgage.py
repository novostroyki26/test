import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_regular_mortgage() -> None:
    params = {"price": 10_000_000, "down": 2_000_000, "rate": 12, "years": 20}
    response = client.get("/mortgage", params=params)
    assert response.status_code == 200
    assert response.json() == {"monthly_payment": 88086.89, "overpayment": 13140853.76}


def test_zero_rate() -> None:
    params = {"price": 1_000_000, "down": 100_000, "rate": 0, "years": 3}
    response = client.get("/mortgage", params=params)
    assert response.status_code == 200
    assert response.json() == {"monthly_payment": 25000.0, "overpayment": 0.0}


def test_max_rate_is_allowed() -> None:
    params = {"price": 1_000_000, "down": 0, "rate": 50, "years": 1}
    assert client.get("/mortgage", params=params).status_code == 200


@pytest.mark.parametrize(
    "override",
    [
        {"price": 0},
        {"price": -1},
        {"years": 0},
        {"years": -5},
        {"down": -1},
        {"down": 1_000_000},
        {"down": 1_500_000},
        {"rate": -0.1},
        {"rate": 50.1},
    ],
    ids=[
        "price-zero",
        "price-negative",
        "years-zero",
        "years-negative",
        "down-negative",
        "down-equals-price",
        "down-above-price",
        "rate-below-0",
        "rate-above-50",
    ],
)
def test_invalid_params_return_422(override: dict[str, float]) -> None:
    params: dict[str, float] = {"price": 1_000_000, "down": 100_000, "rate": 10, "years": 10}
    params.update(override)
    assert client.get("/mortgage", params=params).status_code == 422
