# AEGIS ForkGuard Server Launcher with Integrated Dashboard UI & REST API

import os
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import jaclang
import main as jac_main

# Initialize FastAPI app
app = FastAPI(
    title="AEGIS ForkGuard",
    description="Counterfactual Execution Firewall for AI Agents built with Jaclang",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/health")
def health_check():
    return {"status": "online", "system": "AEGIS ForkGuard Firewall (Jac 0.16.7)"}

@app.post("/walker/run_vulnerable_api")
async def run_vulnerable_api(data: dict):
    payload = data.get("payload", {})
    result = jac_main.run_vulnerable_mode(payload)
    return {"ok": True, "data": {"reports": [result]}}

@app.post("/walker/run_forkguard_api")
async def run_forkguard_api(data: dict):
    payload = data.get("payload", {})
    result = jac_main.run_forkguard_mode(payload)
    return {"ok": True, "data": {"reports": [result]}}

@app.get("/api/demo/safe_invoice")
def get_safe_invoice():
    return jac_main.get_demo_safe_invoice()

@app.get("/api/demo/attacked_invoice")
def get_attacked_invoice():
    return jac_main.get_demo_attacked_invoice()

# Mount static frontend assets
frontend_dir = os.path.join(os.path.dirname(__file__), "frontend")
if os.path.exists(frontend_dir):
    app.mount("/static", StaticFiles(directory=frontend_dir), name="static")

@app.get("/")
def serve_index():
    index_file = os.path.join(frontend_dir, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
    return JSONResponse({"message": "AEGIS ForkGuard Server Online"})

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
