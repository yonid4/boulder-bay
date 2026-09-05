from fastapi import FastAPI

app = FastAPI(title="Boulder Bay")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
