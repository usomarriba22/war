from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timezone

app = FastAPI(title="CON War Room API", version="0.9.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AdvisorRequest(BaseModel):
    game_state: dict
    question: str = "Analiza la partida."

class MovementRequest(BaseModel):
    game_state: dict
    marks: list = []

@app.get("/health")
def health():
    return {"status": "ok", "service": "warroom-api", "version": "0.9.0", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/api/status")
def status():
    return {"project": "CON War Room", "phase": "v0.9-ocr-movement", "modules": ["advisor", "movement", "ocr-foundation", "multi-game"]}

def resource_alerts(resources):
    alerts = []
    for key, data in (resources or {}).items():
        if isinstance(data, dict) and data.get("status") in ["critical", "low"]:
            alerts.append(f"{key}: {data.get('status')} stock={data.get('value')} +{data.get('hour')}/h")
    return alerts

def advisor_text(game, question):
    alerts = resource_alerts(game.get("resources", {}))
    fronts = game.get("fronts", [])
    high = [f.get("name", "frente") for f in fronts if f.get("risk") in ["high", "critical"]]
    return f"""CON WAR ROOM ADVISOR

Partida: {game.get('name')} / {game.get('country')} / Dia {game.get('day')}
VP: {game.get('victory_points')}
Coalicion: {", ".join(game.get('coalition', [])) if isinstance(game.get('coalition', []), list) else game.get('coalition')}

Alertas economicas:
{chr(10).join("- " + a for a in alerts) if alerts else "- Sin alertas criticas"}

Frentes de riesgo:
{", ".join(high) if high else "sin frentes high/critical"}

Orden proximas 6-12 horas:
1. No abras guerras nuevas si hay fuel/rares/electronica bajos.
2. Cierra frentes activos antes de atacar otro pais.
3. No muevas unidades caras sin radar + antiaereo.
4. Si el frente es urbano, espera organizacion alta antes de entrar.
5. Mantener guarniciones en ciudades conquistadas.
6. Generar snapshot despues de cada captura/OCR.

Pregunta:
{question}
"""

@app.post("/api/advisor/analyze")
def advisor(payload: AdvisorRequest):
    return {"mode": "local-v09", "answer": advisor_text(payload.game_state, payload.question)}

@app.post("/api/movement/analyze")
def movement(payload: MovementRequest):
    game = payload.game_state
    stacks = game.get("stacks", [])
    enemies = game.get("enemy", [])
    fronts = game.get("fronts", [])
    marks = payload.marks or []
    resources = game.get("resources", {})

    no_move = []
    move = []
    counters = []

    fuel_status = resources.get("fuel", {}).get("status")
    rare_status = resources.get("rares", {}).get("status")
    electronics_status = resources.get("electronics", {}).get("status")

    if fuel_status in ["critical", "low"]:
        no_move.append("Evita movimientos navales/aereos largos: fuel bajo.")
    if rare_status in ["critical", "low"]:
        no_move.append("No encadenes elites ni investigaciones caras: rares bajos.")
    if electronics_status in ["critical", "low"]:
        no_move.append("Cuidado con radar/SAM/satelite: electronica baja.")

    for s in stacks:
        name = s.get("name", "stack")
        loc = s.get("location", "N/A")
        threat = s.get("threat", "medium")
        mission = s.get("mission", "")
        cond = s.get("condition", "")
        if threat in ["high", "critical"]:
            move.append(f"{name} en {loc}: mover solo con apoyo/recon. Mision: {mission}. Condicion: {cond}.")
            no_move.append(f"No mandes {name} aislado ni sin cobertura AA/radar.")
        else:
            move.append(f"{name} en {loc}: puede mantener/avanzar limitado si no abre sobreextension.")

    for e in enemies:
        obs = (e.get("observed") or "").lower()
        loc = e.get("location", "enemigo")
        if "air" in obs or "avion" in obs or "helic" in obs:
            counters.append(f"{loc}: amenaza aerea -> SAM/AA movil + radar; no stacks sin cobertura.")
        elif "nav" in obs or "barco" in obs or "fragata" in obs:
            counters.append(f"{loc}: amenaza naval -> fragata/submarino; no transporte solo.")
        elif "tank" in obs or "armor" in obs or "blind" in obs:
            counters.append(f"{loc}: blindados -> helicoptero ataque / AT / artilleria; evita infanteria sola.")
        else:
            counters.append(f"{loc}: {e.get('counter', 'hacer recon antes de atacar')}")

    high_fronts = [f for f in fronts if f.get("risk") in ["high", "critical"]]
    for f in high_fronts:
        move.append(f"Prioridad frente {f.get('name')}: {f.get('action')}.")

    if marks:
        move.append(f"Hay {len(marks)} marcas tacticas en captura. Usalas como objetivos/referencias para decidir ruta.")
        for i, m in enumerate(marks[:8], 1):
            move.append(f"Marca {i}: {m.get('label')} en x={m.get('x'):.1f}% y={m.get('y'):.1f}%.")

    plan = f"""MOVEMENT ADVISOR

MOVER / ACCIONAR:
{chr(10).join("- " + x for x in move) if move else "- Mantener posicion y hacer recon."}

NO MOVER:
{chr(10).join("- " + x for x in no_move) if no_move else "- Sin restricciones criticas detectadas."}

CONTRAMEDIDAS:
{chr(10).join("- " + x for x in counters) if counters else "- Sin enemigos cargados; actualiza contactos."}

ORDEN PRACTICA:
1. Marca en Capture los objetivos/enemigos importantes.
2. Actualiza stacks propios y enemigos observados.
3. Usa esta recomendacion como checklist antes de mover.
4. No ejecutes movimientos caros si fuel/rares/electronica siguen bajos.
"""
    return {"mode": "movement-local-v09", "plan": plan}