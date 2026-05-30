from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timezone
import json

app = FastAPI(
    title="CON War Room API",
    version="0.5.0",
    description="Backend tactico multi-partida para CON War Room."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AdvisorRequest(BaseModel):
    game_state: dict
    question: str = "Dame la mejor decision estrategica para las proximas 6-12 horas."

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "warroom-api",
        "version": "0.5.0",
        "time": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/status")
def status():
    return {
        "project": "CON War Room",
        "phase": "multi-game-war-room",
        "mode": "multi-game-tactical-dashboard",
        "data_source": "browser-localstorage-v0.5",
        "modules": [
            "multi-game",
            "resources",
            "snapshots",
            "fronts",
            "research",
            "advisor-export",
            "local-advisor",
            "future-ocr-ingestion",
            "future-supabase"
        ]
    }

def risk_from_resources(resources: dict) -> list:
    alerts = []
    fuel = resources.get("fuel", {})
    rares = resources.get("rares", {})
    electronics = resources.get("electronics", {})

    if isinstance(fuel, dict) and int(fuel.get("value", 0) or 0) < 1000:
        alerts.append("Fuel bajo/critico: evita spam naval/aereo y prioriza economia de fuel.")
    if isinstance(rares, dict) and int(rares.get("value", 0) or 0) < 750:
        alerts.append("Raros bajos/criticos: no encadenes elites/investigaciones caras sin recuperar stock.")
    if isinstance(electronics, dict) and int(electronics.get("value", 0) or 0) < 1000:
        alerts.append("Electronica baja: cuidado con radar, aviones, satelite y SAM en cola.")

    return alerts

def local_advisor(game_state: dict, question: str) -> str:
    resources = game_state.get("resources", {})
    fronts = game_state.get("fronts", [])
    research = game_state.get("research", [])
    country = game_state.get("country", "N/A")
    day = game_state.get("day", "N/A")
    name = game_state.get("name", "N/A")

    alerts = risk_from_resources(resources)

    high_fronts = []
    for f in fronts:
        if isinstance(f, dict) and f.get("risk") in ["high", "critical"]:
            high_fronts.append(f.get("name", "frente sin nombre"))

    resource_lines = []
    for key, data in resources.items():
        if isinstance(data, dict):
            resource_lines.append(
                f"- {key}: {data.get('value', 0)} / +{data.get('hour', 0)}/h / {data.get('status', 'unknown')}"
            )

    front_lines = []
    for f in fronts:
        if isinstance(f, dict):
            front_lines.append(
                f"- {f.get('name','N/A')}: {f.get('state','N/A')} | riesgo {f.get('risk','N/A')} | accion {f.get('action','N/A')}"
            )

    if not alerts:
        alerts.append("No hay alerta economica critica segun umbrales actuales.")

    return f"""CON WAR ROOM ADVISOR — ANALISIS MULTI-PARTIDA

Partida seleccionada:
- Nombre: {name}
- Pais: {country}
- Dia: {day}
- VP: {game_state.get("victory_points", "N/A")}
- Coalicion: {", ".join(game_state.get("coalition", [])) if isinstance(game_state.get("coalition", []), list) else game_state.get("coalition", "N/A")}

Recursos:
{chr(10).join(resource_lines) if resource_lines else "- Sin recursos cargados"}

Frentes:
{chr(10).join(front_lines) if front_lines else "- Sin frentes cargados"}

Investigacion / prioridades:
{", ".join(research) if isinstance(research, list) else research}

Alertas:
{chr(10).join("- " + a for a in alerts)}

Orden recomendada proximas 6-12 horas:
1. No abras guerras nuevas si tienes frentes activos o recursos criticos.
2. Si hay una capital/enemigo principal casi cerrado, termina esa guerra antes de abrir otra.
3. Si Fuel o Raros estan bajos, pausa elites caras y sube industria/local production.
4. Prioriza radar + antiaereo antes de mover Railgun a zona peligrosa.
5. Si tienes costa expuesta, mantén defensa naval minima y no sobreinviertas si Fuel esta critico.
6. Usa snapshots cada vez que cambies de partida para comparar evolucion.
7. La siguiente decision debe basarse en el recurso limitante, no en lo que apetece investigar.

Pregunta recibida:
{question}
"""

@app.post("/api/advisor/analyze")
def advisor_analyze(payload: AdvisorRequest):
    return {
        "mode": "local-rules-v0.5",
        "answer": local_advisor(payload.game_state, payload.question)
    }

@app.post("/api/advisor/export")
def advisor_export(payload: AdvisorRequest):
    game_state = payload.game_state
    return {
        "export": local_advisor(game_state, payload.question)
    }
