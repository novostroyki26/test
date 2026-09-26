from fastapi import FastAPI

app = FastAPI(title="test")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "hello"}
