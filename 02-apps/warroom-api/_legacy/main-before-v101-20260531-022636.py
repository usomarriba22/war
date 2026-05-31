from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import json, re

app = FastAPI(title="CON War Room API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

TELEMETRY_EVENTS: List[dict] = []
LATEST_RESOURCES: Dict[str, dict] = {}

RESOURCE_ALIASES = {
    "supplies": ["supplies", "supply", "sup", "suministros"],
    "components": ["components", "component", "cmp", "componentes"],
    "fuel": ["fuel", "gas", "oil", "combustible"],
    "electronics": ["electronics", "electronic", "elec", "elc", "electronica"],
    "rares": ["rares", "rare", "rare materials", "raros"],
    "manpower": ["manpower", "population", "recruits", "mano de obra"],
    "money": ["money", "cash", "credits", "gold", "dinero"]
}

class AdvisorRequest(BaseModel):
    game_state: dict
    question: str = "Analiza la partida."

class MovementRequest(BaseModel):
    game_state: dict
    marks: list = []

class TelemetryPayload(BaseModel):
    source: str
    ts: Optional[str] = None
    url: Optional[str] = None
    title: Optional[str] = None
    visible_text: Optional[str] = None
    network: Optional[dict] = None
    reason: Optional[str] = None
    meta: Optional[dict] = None

@app.get("/health")
def health():
    return {"status": "ok", "service": "warroom-api", "version": "1.0.0", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/api/status")
def status():
    return {"project": "CON War Room", "phase": "v1.0-auto-telemetry", "modules": ["telemetry-extension", "auto-ingest", "advisor", "movement"]}

def safe_number(value: Any):
    if isinstance(value, bool): return None
    if isinstance(value, (int, float)): return float(value)
    if isinstance(value, str):
        cleaned = value.strip().replace(",", "").replace(" ", "")
        if re.fullmatch(r"-?\d+(\.\d+)?", cleaned): return float(cleaned)
    return None

def walk_json(obj: Any, path: str = ""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk_json(v, f"{path}.{k}" if path else str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_json(v, f"{path}[{i}]")
    else:
        yield path, obj

def parse_json_maybe(text: str):
    try: return json.loads(text)
    except Exception: return None

def detect_resource_from_path(path: str):
    p = path.lower()
    for resource, aliases in RESOURCE_ALIASES.items():
        if any(alias in p for alias in aliases):
            return resource
    return None

def scan_resources_from_json(obj: Any):
    found = {}
    for path, value in walk_json(obj):
        resource = detect_resource_from_path(path)
        if not resource: continue
        num = safe_number(value)
        if num is None: continue
        p = path.lower()
        field = "hour" if any(x in p for x in ["hour","perhour","production","prod","income","rate","delta"]) else "value"
        found.setdefault(resource, {})
        current = found[resource].get(field)
        if current is None or abs(num) > abs(current):
            found[resource][field] = num
            found[resource][f"{field}_path"] = path
    return found

def scan_resources_from_text(text: str):
    found = {}
    if not text: return found
    lower = text.lower()
    for resource, aliases in RESOURCE_ALIASES.items():
        for alias in aliases:
            idx = lower.find(alias)
            if idx == -1: continue
            window = text[max(0, idx - 80): idx + 180]
            nums = [safe_number(x) for x in re.findall(r"[-+]?\d[\d,\.]*", window)]
            nums = [x for x in nums if x is not None]
            if nums:
                found.setdefault(resource, {})
                found[resource]["value"] = nums[0]
                if len(nums) > 1: found[resource]["hour"] = nums[1]
                found[resource]["text_window"] = window[:300]
            break
    return found

def merge_resource_candidates(candidates: Dict[str, dict], source: str):
    changed = {}
    for resource, data in candidates.items():
        if not data: continue
        LATEST_RESOURCES.setdefault(resource, {})
        for key in ["value", "hour"]:
            if key in data and data[key] is not None:
                LATEST_RESOURCES[resource][key] = data[key]
                LATEST_RESOURCES[resource][f"{key}_source"] = source
                LATEST_RESOURCES[resource]["updated_at"] = datetime.now(timezone.utc).isoformat()
                changed.setdefault(resource, {})[key] = data[key]
    return changed

@app.post("/api/telemetry/ingest")
def ingest_telemetry(payload: TelemetryPayload):
    event = payload.model_dump()
    event["received_at"] = datetime.now(timezone.utc).isoformat()
    candidates = {}
    if payload.visible_text:
        candidates.update(scan_resources_from_text(payload.visible_text))
    if payload.network and isinstance(payload.network, dict):
        body = payload.network.get("body")
        if isinstance(body, str):
            parsed = parse_json_maybe(body)
            candidates.update(scan_resources_from_json(parsed) if parsed is not None else scan_resources_from_text(body))
    changed = merge_resource_candidates(candidates, payload.source)
    event["resource_candidates"] = candidates
    event["resource_changes"] = changed
    TELEMETRY_EVENTS.append(event)
    if len(TELEMETRY_EVENTS) > 200: del TELEMETRY_EVENTS[:-200]
    return {"status": "ok", "received_at": event["received_at"], "candidates": candidates, "changed": changed}

@app.get("/api/telemetry/latest")
def latest_telemetry():
    return {"count": len(TELEMETRY_EVENTS), "latest": TELEMETRY_EVENTS[-1] if TELEMETRY_EVENTS else None, "resources": LATEST_RESOURCES}

@app.get("/api/telemetry/events")
def telemetry_events(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"events": TELEMETRY_EVENTS[-limit:]}

@app.get("/api/telemetry/resources")
def telemetry_resources():
    return {"resources": LATEST_RESOURCES, "updated_at": datetime.now(timezone.utc).isoformat()}

def advisor_text(game, question):
    resources = game.get("resources", {})
    low = [f"{k}: {v.get('status')} stock={v.get('value')} +{v.get('hour')}/h" for k, v in resources.items() if isinstance(v, dict) and v.get("status") in ["critical", "low"]]
    high = [f.get("name", "frente") for f in game.get("fronts", []) if f.get("risk") in ["high", "critical"]]
    return f"""CON WAR ROOM ADVISOR

Partida: {game.get('name')} / {game.get('country')} / Dia {game.get('day')}
VP: {game.get('victory_points')}

Alertas economicas:
{chr(10).join("- " + a for a in low) if low else "- Sin alertas criticas"}

Frentes de riesgo:
{", ".join(high) if high else "sin frentes high/critical"}

Orden:
1. No abras guerras nuevas si hay fuel/rares/electronica bajos.
2. Cierra frentes activos antes de atacar otro pais.
3. No muevas unidades caras sin radar + antiaereo.
4. Mantener guarniciones en ciudades conquistadas.

Pregunta:
{question}
"""

@app.post("/api/advisor/analyze")
def advisor(payload: AdvisorRequest):
    return {"mode": "local-v100", "answer": advisor_text(payload.game_state, payload.question)}

@app.post("/api/movement/analyze")
def movement(payload: MovementRequest):
    game = payload.game_state
    marks = payload.marks or []
    resources = game.get("resources", {})
    lines = ["MOVEMENT ADVISOR", "", "MOVER / ACCIONAR:"]
    for f in [f for f in game.get("fronts", []) if f.get("risk") in ["high", "critical"]]:
        lines.append(f"- Prioridad frente {f.get('name')}: {f.get('action')}.")
    for s in game.get("stacks", []):
        threat = s.get("threat", "medium")
        lines.append(f"- {s.get('name','stack')} en {s.get('location','N/A')}: {'mover solo con apoyo/recon' if threat in ['high','critical'] else 'mantener o avanzar limitado'}.")
    lines += ["", "NO MOVER:"]
    if resources.get("fuel", {}).get("status") in ["critical", "low"]: lines.append("- Evita movimientos navales/aereos largos: fuel bajo.")
    if resources.get("rares", {}).get("status") in ["critical", "low"]: lines.append("- No encadenes elites/investigaciones caras: rares bajos.")
    if resources.get("electronics", {}).get("status") in ["critical", "low"]: lines.append("- Cuidado con radar/SAM/satelite: electronica baja.")
    if len(lines) < 6: lines.append("- Sin restricciones criticas detectadas.")
    lines += ["", "MARCAS:"]
    if marks:
        for i, m in enumerate(marks[:8], 1):
            lines.append(f"- Marca {i}: {m.get('label')} x={float(m.get('x', 0)):.1f}% y={float(m.get('y', 0)):.1f}%")
    else:
        lines.append("- Sin marcas cargadas.")
    return {"mode": "movement-local-v100", "plan": "\n".join(lines)}