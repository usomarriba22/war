from fastapi import FastAPI
from datetime import datetime, timezone

app = FastAPI(
    title="CON War Room API",
    version="0.1.0",
    description="Backend tactico para CON War Room."
)

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "warroom-api",
        "time": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/status")
def status():
    return {
        "project": "CON War Room",
        "phase": "kubernetes-ci-cd-lab",
        "mode": "tactical-dashboard",
        "modules": [
            "resources",
            "cities",
            "research",
            "fronts",
            "stacks",
            "advisor-export",
            "ocr-ingestion"
        ]
    }

@app.get("/api/advisor/sample")
def advisor_sample():
    return {
        "game": "World War 3 - Colombia",
        "strategic_state": "early expansion",
        "alerts": [
            "No abrir mas guerras todavia",
            "Estabilizar ciudades conquistadas",
            "Subir economia antes de elites caras"
        ],
        "recommended_next_actions": [
            "Cerrar Ecuador",
            "Mantener guarnicion en Panama",
            "Investigar radar y antiaereo",
            "Preparar Railgun despues de estabilizar recursos"
        ]
    }
