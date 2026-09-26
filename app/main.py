from fastapi import FastAPI, HTTPException, Query

app = FastAPI(title="test")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "hello"}


@app.get("/mortgage")
def mortgage(
    price: float = Query(gt=0),
    down: float = Query(ge=0),
    rate: float = Query(ge=0, le=50),
    years: int = Query(gt=0),
) -> dict[str, float]:
    if down >= price:
        raise HTTPException(status_code=422, detail="down must be less than price")
    principal = price - down
    months = years * 12
    monthly_rate = rate / 100 / 12
    if monthly_rate == 0:
        payment = principal / months
    else:
        payment = principal * monthly_rate / (1 - (1 + monthly_rate) ** -months)
    return {
        "monthly_payment": round(payment, 2),
        "overpayment": round(payment * months - principal, 2),
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict[str, str]:
    return {"version": "0.1.0"}


@app.get("/commission")
def commission(
    price: float = Query(gt=0),
    percent: float = Query(default=3, gt=0, le=20),
    min_commission: float = Query(default=50_000, ge=0),
) -> dict[str, float]:
    amount = max(price * percent / 100, min_commission)
    return {"commission": round(amount, 2), "percent": percent, "price": price}
