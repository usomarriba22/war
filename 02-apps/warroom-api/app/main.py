from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone

app = FastAPI(
    title="CON War Room API",
    version="0.2.0",
    description="Backend tactico para CON War Room."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
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
        "phase": "tactical-web-dashboard",
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

@app.get("/api/game/demo")
def game_demo():
    return {
        "game": "World War 3 - Colombia",
        "country": "Colombia",
        "day": 2,
        "victory_points": "432 / 5920",
        "coalition": ["Venezuela", "USA", "Canada", "Bolivia"],
        "resources": {
            "supplies": {"value": 7079, "hour": 91, "status": "stable"},
            "components": {"value": 5474, "hour": 45, "status": "stable"},
            "fuel": {"value": 345, "hour": 50, "status": "critical"},
            "electronics": {"value": 719, "hour": 49, "status": "low"},
            "rares": {"value": 84, "hour": 34, "status": "critical"},
            "manpower": {"value": 3557, "hour": 48, "status": "stable"},
            "money": {"value": 32968, "hour": 382, "status": "stable"}
        },
        "fronts": [
            {"name": "Panama", "state": "occupied", "risk": "medium", "action": "keep garrison"},
            {"name": "Ecuador / Quito", "state": "active offensive", "risk": "high", "action": "finish and stabilize"},
            {"name": "Peru", "state": "next possible target", "risk": "medium", "action": "do not attack yet"},
            {"name": "Caribbean", "state": "naval watch", "risk": "medium", "action": "prepare frigates"}
        ],
        "research_priority": [
            "Radar movil",
            "Antiaereo movil / SAM",
            "Fragata",
            "Railgun",
            "Satelite",
            "Submarino elite"
        ],
        "alerts": [
            "Fuel critico: evitar expansion naval innecesaria",
            "Raros criticos: pausar elites hasta recuperar economia",
            "No abrir mas guerras hasta estabilizar Ecuador y Panama",
            "Railgun debe ir con radar y antiaereo"
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

@app.get("/api/advisor/export")
def advisor_export():
    return {
        "export": """PARTIDA: World War 3 - Colombia
PAIS: Colombia
DIA: 2
COALICION: Venezuela, USA, Canada, Bolivia

RECURSOS:
- Fuel: critico
- Raros: critico
- Electronica: baja
- Componentes: estable

FRENTES:
- Panama: ocupado, mantener guarnicion
- Ecuador/Quito: ofensiva activa, cerrar y estabilizar
- Peru: siguiente objetivo posible, no atacar aun
- Caribe: vigilancia naval

ORDEN RECOMENDADA:
1. No abrir mas guerras.
2. Terminar Quito.
3. Mantener guarnicion en Panama.
4. Subir economia homeland.
5. Investigar radar + antiaereo.
6. Preparar Railgun protegido.

PREGUNTA:
Que hago en las proximas 6-12 horas?"""
    }
