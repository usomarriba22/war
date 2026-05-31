
# CON War Room v1.0.4 — Parser Quarantine + Game State Inspector
# Ejecutar desde VS Code PowerShell:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$apiPath = ".\02-apps\warroom-api\app\main.py"
if (!(Test-Path $apiPath)) { throw "No existe API main.py: $apiPath" }

New-Item -ItemType Directory -Force -Path ".\02-apps\warroom-api\_legacy" | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $apiPath ".\02-apps\warroom-api\_legacy\main-before-v104-$stamp.py" -Force -ErrorAction SilentlyContinue

$api = @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse, parse_qs
import json
import re

app = FastAPI(title="CON War Room API", version="1.0.4")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TELEMETRY_EVENTS: List[dict] = []
LATEST_RESOURCES: Dict[str, dict] = {}
GAME_STATE_SNAPSHOTS: List[dict] = []

RESOURCE_KEYS = ["supplies", "components", "fuel", "electronics", "rares", "manpower", "money"]

NOISE_DOMAINS = [
    "google-analytics.com",
    "region1.google-analytics.com",
    "www.google-analytics.com",
    "www.google.com",
    "google.com",
    "googletagmanager.com",
    "pixel-config.reddit.com",
    "reddit.com",
    "s.yimg.com",
    "yimg.com",
    "doubleclick.net",
    "facebook.com",
    "bing.com"
]

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
    return {"status": "ok", "service": "warroom-api", "version": "1.0.4", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/api/status")
def status():
    return {
        "project": "CON War Room",
        "phase": "v1.0.4-parser-quarantine-inspector",
        "modules": ["telemetry-extension", "game-state-inspector", "safe-parser", "advisor", "movement"]
    }

def event_domain(event: dict) -> str:
    network = event.get("network") or {}
    url = network.get("request_url") or network.get("frame_url") or event.get("url") or ""
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""

def is_noise_event(event: dict) -> bool:
    domain = event_domain(event)
    return any(noise in domain for noise in NOISE_DOMAINS)

def safe_number(value: Any):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = value.strip().replace(",", "").replace(" ", "")
        if re.fullmatch(r"-?\d+(\.\d+)?", cleaned):
            return float(cleaned)
    return None

def parse_json_maybe(text: str):
    try:
        return json.loads(text)
    except Exception:
        return None

def walk_json(obj: Any, path: str = ""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            next_path = f"{path}.{k}" if path else str(k)
            yield from walk_json(v, next_path)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_json(v, f"{path}[{i}]")
    else:
        yield path, obj

def looks_like_game_state_body(text: str) -> bool:
    if not text:
        return False
    return (
        "UltAutoGameState" in text or
        "UltMapState" in text or
        "UltArmyState" in text or
        '"stateType"' in text or
        '"dayOfGame"' in text
    )

def get_nested(obj, keys, default=None):
    cur = obj
    for key in keys:
        if isinstance(cur, dict):
            cur = cur.get(key)
        else:
            return default
    return cur if cur is not None else default

def summarize_game_state(parsed: Any, body: str, network: dict):
    result = parsed.get("result") if isinstance(parsed, dict) else None
    states = None
    if isinstance(result, dict):
        states = result.get("states")
    if isinstance(states, dict) and states.get("@c") == "java.util.HashMap":
        state_map = {k: v for k, v in states.items() if k != "@c"}
    elif isinstance(states, dict):
        state_map = states
    else:
        state_map = {}

    summary = {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "request_url": network.get("request_url"),
        "kind": network.get("kind"),
        "body_length": len(body or ""),
        "state_keys": list(state_map.keys()),
        "state_types": {},
        "map": {},
        "counts": {
            "locations": 0,
            "armies": 0,
            "players": 0
        }
    }

    for key, state in state_map.items():
        if not isinstance(state, dict):
            continue
        cls = state.get("@c")
        summary["state_types"][key] = cls

        if cls == "ultshared.UltMapState":
            game_map = state.get("map") or {}
            summary["map"] = {
                "mapID": game_map.get("mapID"),
                "dayOfGame": game_map.get("dayOfGame"),
                "width": game_map.get("width"),
                "height": game_map.get("height"),
                "version": game_map.get("version")
            }
            locs = game_map.get("locations")
            if isinstance(locs, list) and len(locs) > 1 and isinstance(locs[1], list):
                summary["counts"]["locations"] = len(locs[1])

        if cls == "ultshared.UltArmyState":
            armies = state.get("armies") or {}
            if isinstance(armies, dict):
                summary["counts"]["armies"] = len([k for k in armies.keys() if k != "@c"])

        if "player" in str(cls).lower():
            summary["counts"]["players"] += 1

    return summary

def store_game_state(body: str, network: dict):
    parsed = parse_json_maybe(body)
    if parsed is None:
        return None

    summary = summarize_game_state(parsed, body, network)

    # Guardamos full body en memoria para inspección controlada.
    snap = {
        "received_at": summary["received_at"],
        "summary": summary,
        "body": body
    }
    GAME_STATE_SNAPSHOTS.append(snap)
    if len(GAME_STATE_SNAPSHOTS) > 10:
        del GAME_STATE_SNAPSHOTS[:-10]

    return summary

def extract_explicit_resources(parsed: Any):
    """
    Parser seguro: SOLO actualiza recursos si existe una estructura explícita con los 7 nombres.
    Ya no hacemos generic scan por paths porque eso generaba basura:
    components=5, fuel=0, electronics=1, manpower=-60, etc.
    """
    found = {}

    def try_resource_obj(obj):
        if not isinstance(obj, dict):
            return None

        lower_keys = {str(k).lower(): k for k in obj.keys()}
        hits = [rk for rk in RESOURCE_KEYS if rk in lower_keys]
        if len(hits) < 4:
            return None

        candidate = {}
        for rk in RESOURCE_KEYS:
            if rk not in lower_keys:
                continue
            raw = obj[lower_keys[rk]]
            if isinstance(raw, dict):
                value = safe_number(raw.get("value") or raw.get("stock") or raw.get("amount") or raw.get("current"))
                hour = safe_number(raw.get("hour") or raw.get("perHour") or raw.get("production") or raw.get("prod") or raw.get("rate"))
            else:
                value = safe_number(raw)
                hour = None

            if value is not None or hour is not None:
                candidate[rk] = {}
                if value is not None:
                    candidate[rk]["value"] = value
                if hour is not None:
                    candidate[rk]["hour"] = hour

        return candidate if candidate else None

    direct = try_resource_obj(parsed)
    if direct:
        return direct

    if isinstance(parsed, dict):
        for path, value in walk_json(parsed):
            if not isinstance(value, dict):
                continue
            direct = try_resource_obj(value)
            if direct:
                return direct

    return found

def merge_resource_candidates(candidates: Dict[str, dict], source: str):
    changed = {}
    for resource, data in candidates.items():
        if resource not in RESOURCE_KEYS:
            continue
        if not isinstance(data, dict):
            continue

        LATEST_RESOURCES.setdefault(resource, {})
        for key in ["value", "hour"]:
            if key in data and data[key] is not None:
                LATEST_RESOURCES[resource][key] = data[key]
                LATEST_RESOURCES[resource][f"{key}_source"] = source
                LATEST_RESOURCES[resource]["updated_at"] = datetime.now(timezone.utc).isoformat()
                changed.setdefault(resource, {})[key] = data[key]

    return changed

def candidate_paths(terms: List[str], limit: int = 200):
    if not GAME_STATE_SNAPSHOTS:
        return []

    parsed = parse_json_maybe(GAME_STATE_SNAPSHOTS[-1]["body"])
    if parsed is None:
        return []

    terms_l = [t.lower() for t in terms]
    hits = []

    for path, value in walk_json(parsed):
        joined = f"{path} {value}".lower()
        if any(t in joined for t in terms_l):
            hits.append({
                "path": path,
                "value": value if isinstance(value, (str, int, float, bool)) or value is None else str(type(value)),
            })
            if len(hits) >= limit:
                break

    return hits

@app.post("/api/telemetry/ingest")
def ingest_telemetry(payload: TelemetryPayload):
    event = payload.model_dump()
    event["received_at"] = datetime.now(timezone.utc).isoformat()

    candidates = {}
    game_state_summary = None

    network = payload.network or {}
    body = network.get("body") if isinstance(network, dict) else None

    if isinstance(body, str) and body:
        parsed = parse_json_maybe(body)

        if looks_like_game_state_body(body):
            game_state_summary = store_game_state(body, network)

        # Solo aceptar recursos si vienen en una estructura explícita.
        if parsed is not None:
            candidates = extract_explicit_resources(parsed)

    changed = merge_resource_candidates(candidates, payload.source)

    # No guardar bodies completos dentro de TELEMETRY_EVENTS para no romper port-forward.
    safe_event = event.copy()
    if isinstance(safe_event.get("network"), dict) and isinstance(safe_event["network"].get("body"), str):
        raw = safe_event["network"]["body"]
        safe_event["network"]["body_length"] = len(raw)
        safe_event["network"]["body"] = raw[:1500]

    safe_event["resource_candidates"] = candidates
    safe_event["resource_changes"] = changed
    safe_event["game_state_summary"] = game_state_summary

    TELEMETRY_EVENTS.append(safe_event)
    if len(TELEMETRY_EVENTS) > 300:
        del TELEMETRY_EVENTS[:-300]

    return {
        "status": "ok",
        "received_at": safe_event["received_at"],
        "candidates": candidates,
        "changed": changed,
        "game_state_summary": game_state_summary
    }

@app.post("/api/telemetry/clear")
def telemetry_clear():
    TELEMETRY_EVENTS.clear()
    LATEST_RESOURCES.clear()
    GAME_STATE_SNAPSHOTS.clear()
    return {"status": "cleared", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/api/telemetry/latest")
def latest_telemetry():
    return {
        "count": len(TELEMETRY_EVENTS),
        "latest": TELEMETRY_EVENTS[-1] if TELEMETRY_EVENTS else None,
        "resources": LATEST_RESOURCES,
        "game_state_count": len(GAME_STATE_SNAPSHOTS)
    }

@app.get("/api/telemetry/resources")
def telemetry_resources():
    return {"resources": LATEST_RESOURCES, "updated_at": datetime.now(timezone.utc).isoformat()}

@app.get("/api/telemetry/latest-resource-state")
def telemetry_latest_resource_state():
    return {
        "resources": LATEST_RESOURCES,
        "event_count": len(TELEMETRY_EVENTS),
        "game_state_count": len(GAME_STATE_SNAPSHOTS),
        "time": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/telemetry/events")
def telemetry_events(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"events": TELEMETRY_EVENTS[-limit:]}

@app.get("/api/telemetry/game-network-light")
def telemetry_game_network_light(limit: int = 10):
    limit = max(1, min(limit, 30))
    items = []

    for event in TELEMETRY_EVENTS:
        network = event.get("network") or {}
        if not network:
            continue
        if is_noise_event(event):
            continue

        body = network.get("body") or ""
        items.append({
            "received_at": event.get("received_at"),
            "kind": network.get("kind"),
            "domain": event_domain(event),
            "request_url": network.get("request_url"),
            "status": network.get("status"),
            "content_type": network.get("content_type"),
            "body_length": network.get("body_length") or (len(body) if isinstance(body, str) else 0),
            "body_preview": body[:300] if isinstance(body, str) else "",
            "game_state_summary": event.get("game_state_summary")
        })

    return {"network": items[-limit:], "resources": LATEST_RESOURCES, "game_state_count": len(GAME_STATE_SNAPSHOTS)}

@app.get("/api/telemetry/game-state-snapshots")
def telemetry_game_state_snapshots():
    return {
        "count": len(GAME_STATE_SNAPSHOTS),
        "snapshots": [x["summary"] for x in GAME_STATE_SNAPSHOTS]
    }

@app.get("/api/telemetry/game-state-latest")
def telemetry_game_state_latest(full: bool = False):
    if not GAME_STATE_SNAPSHOTS:
        return {"available": False, "message": "No game state captured yet."}

    snap = GAME_STATE_SNAPSHOTS[-1]
    if full:
        return {
            "available": True,
            "summary": snap["summary"],
            "body": snap["body"]
        }

    return {
        "available": True,
        "summary": snap["summary"],
        "body_preview": snap["body"][:3000]
    }

@app.get("/api/telemetry/candidate-paths")
def telemetry_candidate_paths(terms: str = "resource,supplies,components,fuel,electronics,rare,manpower,money,stock,production", limit: int = 200):
    term_list = [x.strip() for x in terms.split(",") if x.strip()]
    return {
        "terms": term_list,
        "game_state_count": len(GAME_STATE_SNAPSHOTS),
        "hits": candidate_paths(term_list, limit=max(1, min(limit, 500)))
    }

@app.get("/api/telemetry/domains")
def telemetry_domains(limit: int = 300):
    limit = max(1, min(limit, 1000))
    recent = TELEMETRY_EVENTS[-limit:]
    domains = {}
    kinds = {}

    for event in recent:
        domain = event_domain(event) or "unknown"
        domains[domain] = domains.get(domain, 0) + 1

        network = event.get("network") or {}
        kind = network.get("kind") or event.get("reason") or "unknown"
        kinds[kind] = kinds.get(kind, 0) + 1

    return {
        "total_stored": len(TELEMETRY_EVENTS),
        "checked": len(recent),
        "domains": dict(sorted(domains.items(), key=lambda x: x[1], reverse=True)),
        "kinds": dict(sorted(kinds.items(), key=lambda x: x[1], reverse=True))
    }

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
6. Generar snapshot tras cambios importantes.

Pregunta:
{question}
"""

@app.post("/api/advisor/analyze")
def advisor(payload: AdvisorRequest):
    return {"mode": "local-v104", "answer": advisor_text(payload.game_state, payload.question)}

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

    if resources.get("fuel", {}).get("status") in ["critical", "low"]:
        no_move.append("Evita movimientos navales/aereos largos: fuel bajo.")
    if resources.get("rares", {}).get("status") in ["critical", "low"]:
        no_move.append("No encadenes elites ni investigaciones caras: rares bajos.")
    if resources.get("electronics", {}).get("status") in ["critical", "low"]:
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

    for f in [f for f in fronts if f.get("risk") in ["high", "critical"]]:
        move.append(f"Prioridad frente {f.get('name')}: {f.get('action')}.")

    if marks:
        move.append(f"Hay {len(marks)} marcas tacticas en captura. Usalas como objetivos/referencias para decidir ruta.")
        for i, m in enumerate(marks[:8], 1):
            x = float(m.get("x", 0))
            y = float(m.get("y", 0))
            move.append(f"Marca {i}: {m.get('label')} en x={x:.1f}% y={y:.1f}%.")

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
    return {"mode": "movement-local-v104", "plan": plan}
'@

[System.IO.File]::WriteAllText((Resolve-Path $apiPath), $api, $Utf8NoBom)

Write-Host "v1.0.4 Parser Quarantine + Inspector aplicado."
Write-Host "Siguiente:"
Write-Host "1) git add . ; git commit -m 'Quarantine unsafe resource parser and add game state inspector' ; git push"
Write-Host "2) Build warroom-api + rollout restart"
Write-Host "3) POST /api/telemetry/clear"
Write-Host "4) Abrir una partida desde cero"
Write-Host "5) Probar /api/telemetry/game-state-snapshots y /api/telemetry/candidate-paths"
