from fastapi import FastAPI

app = FastAPI(title="test")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "hello"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict[str, str]:
    return {"version": "0.1.0"}
