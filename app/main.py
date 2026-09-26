from fastapi import FastAPI, Query

app = FastAPI(title="test")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "hello"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/commission")
def commission(
    price: float = Query(gt=0),
    percent: float = Query(default=3, gt=0, le=20),
    min_commission: float = Query(default=50_000, ge=0),
) -> dict[str, float]:
    amount = max(price * percent / 100, min_commission)
    return {"commission": round(amount, 2), "percent": percent, "price": price}
