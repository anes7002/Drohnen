import uvicorn
from server import app  # noqa: F401  — re-export so 'uvicorn main:app' works

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
