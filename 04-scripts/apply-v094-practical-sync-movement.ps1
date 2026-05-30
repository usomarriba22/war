
# CON War Room v0.9.4 — Practical Sync + Movement Control Board
# Ejecutar desde VS Code PowerShell:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$mainPath = ".\02-apps\warroom-web\src\main.jsx"
$cssPath  = ".\02-apps\warroom-web\src\styles.css"
$dataPath = ".\02-apps\warroom-web\src\lib\data.js"

if (!(Test-Path $mainPath)) { throw "No existe $mainPath" }
if (!(Test-Path $cssPath)) { throw "No existe $cssPath" }
if (!(Test-Path $dataPath)) { throw "No existe $dataPath" }

New-Item -ItemType Directory -Force -Path ".\02-apps\warroom-web\_legacy" | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $mainPath ".\02-apps\warroom-web\_legacy\main-before-v094-$stamp.jsx" -Force
Copy-Item $cssPath ".\02-apps\warroom-web\_legacy\styles-before-v094-$stamp.css" -Force

# Mantener data.js, solo asegurar keys/meta limpios
$dataJs = @'
export const RESOURCE_KEYS = ["supplies", "components", "fuel", "electronics", "rares", "manpower", "money"];

export const RESOURCE_META = {
  supplies: { label: "Supplies", short: "SUP", img: "/assets/resources/supplies.svg", target: 5000 },
  components: { label: "Components", short: "CMP", img: "/assets/resources/components.svg", target: 4500 },
  fuel: { label: "Fuel", short: "FUL", img: "/assets/resources/fuel.svg", target: 3500 },
  electronics: { label: "Electronics", short: "ELC", img: "/assets/resources/electronics.svg", target: 2500 },
  rares: { label: "Rares", short: "RAR", img: "/assets/resources/rares.svg", target: 1800 },
  manpower: { label: "Manpower", short: "MAN", img: "/assets/resources/manpower.svg", target: 3000 },
  money: { label: "Money", short: "MON", img: "/assets/resources/money.svg", target: 20000 }
};

export const STORAGE_KEY = "con-war-room-games-v09";
export const API_BASE = "http://127.0.0.1:8000";

export function deriveStatus(key, value) {
  const target = RESOURCE_META[key]?.target || 1000;
  const n = Number(value || 0);
  if (n < target * 0.25) return "critical";
  if (n < target * 0.55) return "low";
  return "stable";
}

export function baseGame(id, name, country) {
  return {
    id,
    name,
    country,
    day: 1,
    victory_points: "0 / 5920",
    phase: "early expansion",
    coalition: [],
    resources: Object.fromEntries(RESOURCE_KEYS.map(k => [k, { value: 0, hour: 0, status: "critical" }])),
    fronts: [{ name: "Frente 1", state: "pendiente", risk: "medium", action: "actualizar" }],
    stacks: [
      { name: "Stack principal", location: "capital / frente", units: "infanteria + recon", mission: "defensa", condition: "100%", threat: "medium", order: "mantener" }
    ],
    enemy: [
      { location: "frente enemigo", observed: "desconocido", risk: "medium", counter: "recon + radar antes de atacar" }
    ],
    research: [],
    notes: "",
    snapshots: [],
    feed: [],
    updated_at: new Date().toISOString(),
    live_base_at: new Date().toISOString()
  };
}

export function seedGames() {
  const g = baseGame("colombia-main", "Colombia Principal", "Colombia");
  g.day = 6;
  g.victory_points = "550 / 5920";
  g.coalition = ["Venezuela", "USA", "Canada", "Bolivia"];
  g.resources = {
    supplies: { value: 1857, hour: 119, status: "low" },
    components: { value: 2704, hour: 69, status: "stable" },
    fuel: { value: 928, hour: 64, status: "low" },
    electronics: { value: 481, hour: 60, status: "critical" },
    rares: { value: 217, hour: 43, status: "critical" },
    manpower: { value: 1206, hour: 49, status: "low" },
    money: { value: 13764, hour: 485, status: "low" }
  };
  g.fronts = [
    { name: "Panama", state: "ocupado", risk: "medium", action: "mantener guarnicion" },
    { name: "Ecuador / Quito", state: "ofensiva activa", risk: "high", action: "cerrar y estabilizar" },
    { name: "Peru", state: "siguiente objetivo posible", risk: "medium", action: "no atacar aun" },
    { name: "Caribe", state: "vigilancia naval", risk: "medium", action: "preparar fragatas" }
  ];
  g.stacks = [
    { name: "Grupo Quito", location: "Ecuador / Quito", units: "infanteria + recon", mission: "tomar ciudad", condition: "70%", threat: "high", order: "avanzar con cautela" },
    { name: "Guarnicion Panama", location: "Panama", units: "infanteria", mission: "control urbano", condition: "100%", threat: "medium", order: "mantener" }
  ];
  g.enemy = [
    { location: "Quito", observed: "defensa urbana probable", risk: "high", counter: "rodear, esperar organizacion, no entrar con unidades danadas" },
    { location: "Caribe", observed: "naval desconocido", risk: "medium", counter: "radar + fragatas; no enviar transporte solo" }
  ];
  g.research = ["Radar movil", "Antiaereo movil/SAM", "Fragata", "Railgun", "Satelite", "Submarino elite"];
  return [g, baseGame("slot-2", "Partida 2", "Pendiente"), baseGame("slot-3", "Partida 3", "Pendiente"), baseGame("slot-4", "Partida 4", "Pendiente")];
}

export function normalizeGame(game) {
  const b = baseGame(game.id || `game-${Date.now()}`, game.name || "Partida", game.country || "Pais");
  return {
    ...b,
    ...game,
    resources: { ...b.resources, ...(game.resources || {}) },
    fronts: game.fronts || b.fronts,
    stacks: game.stacks || b.stacks,
    enemy: game.enemy || b.enemy,
    research: game.research || [],
    snapshots: game.snapshots || [],
    feed: game.feed || []
  };
}

export function readinessScore(game) {
  let score = 100;
  Object.values(game.resources || {}).forEach(r => {
    if (r.status === "critical") score -= 12;
    if (r.status === "low") score -= 6;
  });
  (game.fronts || []).forEach(f => {
    if (f.risk === "critical") score -= 18;
    if (f.risk === "high") score -= 10;
    if (f.risk === "medium") score -= 4;
  });
  return Math.max(0, Math.min(100, score));
}
'@
[System.IO.File]::WriteAllText((Resolve-Path $dataPath), $dataJs, $Utf8NoBom)

$mainJsx = @'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Activity, Bot, Crosshair, Eye, Gamepad2, Radar, Save, ShieldAlert, Target, Video, Zap } from "lucide-react";
import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { API_BASE, RESOURCE_KEYS, RESOURCE_META, STORAGE_KEY, baseGame, deriveStatus, normalizeGame, readinessScore, seedGames } from "./lib/data";
import "./styles.css";

function nowIso() { return new Date().toISOString(); }
function readGames() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) {
    const seeded = seedGames();
    localStorage.setItem(STORAGE_KEY, JSON.stringify(seeded));
    return seeded;
  }
  return JSON.parse(raw).map(normalizeGame);
}
function writeGames(games) { localStorage.setItem(STORAGE_KEY, JSON.stringify(games)); }
function addFeed(game, text, level = "info") {
  return { ...game, feed: [...(game.feed || []), { time: nowIso(), text, level }].slice(-80), updated_at: nowIso() };
}
function applyLiveTick(game) {
  const last = new Date(game.live_base_at || game.updated_at || nowIso()).getTime();
  const diff = Math.max(0, (Date.now() - last) / 1000);
  if (diff < 1) return game;
  const resources = { ...game.resources };
  Object.entries(resources).forEach(([key, r]) => {
    const value = Math.round((Number(r.value || 0) + Number(r.hour || 0) * diff / 3600) * 100) / 100;
    resources[key] = { ...r, value, status: deriveStatus(key, value) };
  });
  return { ...game, resources, live_base_at: nowIso() };
}
function parseNumbers(text) {
  return (text || "")
    .replace(/[^\d,+.\s-]/g, " ")
    .split(/[\s,\/|]+/)
    .map(x => Number(String(x).replace(/[^\d.-]/g, "")))
    .filter(n => Number.isFinite(n));
}
function snapshot(game) {
  return { time: nowIso(), day: game.day, victory_points: game.victory_points, resources: JSON.parse(JSON.stringify(game.resources)), readiness: readinessScore(game) };
}
function criticalEta(game) {
  const entry = Object.entries(game.resources || {}).find(([, r]) => r.status === "critical" || r.status === "low");
  return entry ? `${RESOURCE_META[entry[0]]?.label || entry[0]} bajo` : "OK";
}
function localMovementPlan(game, marks = []) {
  const res = game.resources || {};
  const low = Object.entries(res).filter(([, r]) => ["critical", "low"].includes(r.status)).map(([k, r]) => `${k} ${r.status} (${Math.round(r.value || 0)} +${r.hour || 0}/h)`);
  const highFronts = (game.fronts || []).filter(f => ["high", "critical"].includes(f.risk));
  const stacks = game.stacks || [];
  const enemies = game.enemy || [];

  const lines = [];
  lines.push("MOVEMENT ASSISTANT - PLAN LOCAL");
  lines.push("");
  lines.push("Prioridad ahora:");
  if (highFronts.length) highFronts.forEach(f => lines.push(`- Frente ${f.name}: ${f.action}. Riesgo ${f.risk}.`));
  else lines.push("- Sin frente high/critical. Mantener recon y economia.");

  lines.push("");
  lines.push("Mover:");
  stacks.forEach(s => {
    const risky = ["high", "critical"].includes(s.threat);
    lines.push(`- ${s.name} (${s.location}): ${risky ? "NO avanzar solo; mover con apoyo/radar/AA" : "puede mantener o avanzar limitado"} | mision: ${s.mission} | condicion: ${s.condition}`);
  });

  lines.push("");
  lines.push("No mover:");
  if (res.fuel?.status !== "stable") lines.push("- No hacer desplazamientos navales/aereos largos: fuel bajo.");
  if (res.rares?.status !== "stable") lines.push("- No encadenar elites/investigaciones caras: rares bajo.");
  if (res.electronics?.status !== "stable") lines.push("- No depender de radar/SAM/satelite nuevo sin recuperar electronica.");
  if (!low.length) lines.push("- Sin bloqueo economico critico detectado.");

  lines.push("");
  lines.push("Contramedidas:");
  enemies.forEach(e => lines.push(`- ${e.location}: observado ${e.observed}. Counter: ${e.counter}.`));
  if (!enemies.length) lines.push("- Sin enemigos cargados. Actualiza contactos.");

  lines.push("");
  lines.push("Marcas de captura:");
  if (marks.length) marks.slice(0, 10).forEach((m, i) => lines.push(`- ${i + 1}. ${m.label} en x=${m.x.toFixed(1)}% y=${m.y.toFixed(1)}%`));
  else lines.push("- Sin marcas. Marca objetivos/enemigos en Capture.");

  lines.push("");
  lines.push("Checklist antes de mover:");
  lines.push("1. Revisar organizacion/vida del stack.");
  lines.push("2. Confirmar radar/recon del objetivo.");
  lines.push("3. No dejar ciudades recien tomadas sin guarnicion.");
  lines.push("4. No abrir Peru si Ecuador/Panama no estan estables.");
  return lines.join("\n");
}

function App() {
  const [games, setGames] = useState(readGames);
  const [selectedId, setSelectedId] = useState(() => readGames()[0]?.id);
  const [tab, setTab] = useState("command");
  const [apiOk, setApiOk] = useState(false);
  const [live, setLive] = useState(true);
  const [clock, setClock] = useState(new Date());
  const [advisor, setAdvisor] = useState("Pulsa Ask o Movement.");
  const [movementPlan, setMovementPlan] = useState("Movement listo. Actualiza stacks/enemigos o usa plan local.");
  const [captureStatus, setCaptureStatus] = useState("offline");
  const [captureOpen, setCaptureOpen] = useState(false);
  const [captureMode, setCaptureMode] = useState("fit");
  const [captureSize, setCaptureSize] = useState("compact");
  const [marks, setMarks] = useState([]);
  const [markLabel, setMarkLabel] = useState("objetivo");
  const [syncStock, setSyncStock] = useState("");
  const [syncHour, setSyncHour] = useState("");
  const [syncPreview, setSyncPreview] = useState("");

  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const bigCanvasRef = useRef(null);
  const streamRef = useRef(null);
  const drawTimerRef = useRef(null);

  const selected = useMemo(() => games.find(g => g.id === selectedId) || games[0], [games, selectedId]);

  function persist(next) { setGames(next); writeGames(next); }
  function replaceSelected(nextGame) { persist(games.map(g => g.id === nextGame.id ? { ...nextGame, updated_at: nowIso() } : g)); }
  function patchSelected(patch) { replaceSelected({ ...selected, ...patch }); }

  useEffect(() => {
    const t = setInterval(async () => {
      setClock(new Date());
      try { setApiOk((await fetch(`${API_BASE}/health`, { cache: "no-store" })).ok); } catch { setApiOk(false); }
      if (live) {
        setGames(old => {
          const next = old.map(applyLiveTick);
          writeGames(next);
          return next;
        });
      }
    }, 1000);
    return () => clearInterval(t);
  }, [live]);

  function createGame() {
    const g = baseGame(`game-${Date.now()}`, "Nueva partida", "Pais");
    persist([...games, g]);
    setSelectedId(g.id);
  }
  function deleteGame() {
    if (games.length <= 1) return alert("Debe quedar al menos una partida.");
    if (!confirm(`Borrar ${selected.name}?`)) return;
    const next = games.filter(g => g.id !== selected.id);
    persist(next); setSelectedId(next[0].id);
  }
  function updateResource(key, prop, value) {
    const r = selected.resources[key] || {};
    const nextVal = prop === "value" || prop === "hour" ? Number(value) : value;
    const nextR = { ...r, [prop]: nextVal };
    if (prop !== "status") nextR.status = deriveStatus(key, prop === "value" ? nextVal : nextR.value);
    patchSelected({ resources: { ...selected.resources, [key]: nextR }, live_base_at: nowIso() });
  }
  function saveSnapshot() {
    replaceSelected(addFeed({ ...selected, snapshots: [...(selected.snapshots || []), snapshot(selected)] }, "Snapshot guardado", "info"));
  }

  function previewFastSync() {
    const stock = parseNumbers(syncStock);
    const hour = parseNumbers(syncHour);
    const combo = stock.length >= 14 ? stock : [];
    const stockVals = combo.length >= 14 ? combo.filter((_, i) => i % 2 === 0).slice(0, 7) : stock.slice(0, 7);
    const hourVals = combo.length >= 14 ? combo.filter((_, i) => i % 2 === 1).slice(0, 7) : hour.slice(0, 7);
    setSyncPreview(RESOURCE_KEYS.map((k, i) => `${RESOURCE_META[k].label}: ${stockVals[i] ?? "?"} / +${hourVals[i] ?? "?"}/h`).join("\n"));
  }
  function applyFastSync() {
    const stock = parseNumbers(syncStock);
    const hour = parseNumbers(syncHour);
    const combo = stock.length >= 14 ? stock : [];
    const stockVals = combo.length >= 14 ? combo.filter((_, i) => i % 2 === 0).slice(0, 7) : stock.slice(0, 7);
    const hourVals = combo.length >= 14 ? combo.filter((_, i) => i % 2 === 1).slice(0, 7) : hour.slice(0, 7);
    if (stockVals.length < 7) return alert("Pega 7 stocks o 14 numeros stock/hora.");
    const resources = { ...selected.resources };
    RESOURCE_KEYS.forEach((key, i) => {
      const value = Number(stockVals[i]);
      const h = Number(hourVals[i]);
      resources[key] = {
        ...resources[key],
        value,
        hour: Number.isFinite(h) ? h : resources[key].hour,
        status: deriveStatus(key, value)
      };
    });
    replaceSelected(addFeed({ ...selected, resources, live_base_at: nowIso() }, "Fast Sync aplicado", "info"));
  }

  async function askGeneral() {
    try {
      const res = await fetch(`${API_BASE}/api/advisor/analyze`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ game_state: selected, question: "Analiza la partida y da acciones proximas 6-12 horas." }) });
      const data = await res.json();
      setAdvisor(data.answer || JSON.stringify(data, null, 2));
      replaceSelected(addFeed(selected, "Advisor API generado", "info"));
    } catch (e) {
      const text = localMovementPlan(selected, marks);
      setAdvisor(text);
    }
  }
  async function askMovement() {
    const local = localMovementPlan(selected, marks);
    setMovementPlan(local);
    setAdvisor(local);
    try {
      const res = await fetch(`${API_BASE}/api/movement/analyze`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ game_state: selected, marks }) });
      const data = await res.json();
      const text = data.plan || data.answer || local;
      setMovementPlan(text);
      setAdvisor(text);
      replaceSelected(addFeed(selected, "Movement API generado", "info"));
    } catch {
      replaceSelected(addFeed(selected, "Movement local generado", "info"));
    }
  }

  async function startCapture() {
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: { ideal: 30, max: 60 }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
      streamRef.current = stream;
      const video = videoRef.current;
      video.srcObject = stream; video.muted = true; video.playsInline = true;
      await video.play();
      setCaptureStatus("capturing");
      if (drawTimerRef.current) clearInterval(drawTimerRef.current);
      drawTimerRef.current = setInterval(drawCapture, 1000 / 30);
      stream.getVideoTracks()[0].onended = stopCapture;
    } catch (e) { setCaptureStatus(`denied: ${e.message}`); }
  }
  function stopCapture() {
    if (streamRef.current) streamRef.current.getTracks().forEach(t => t.stop());
    streamRef.current = null;
    if (drawTimerRef.current) clearInterval(drawTimerRef.current);
    drawTimerRef.current = null;
    setCaptureStatus("offline");
  }
  function drawContain(canvas) {
    const video = videoRef.current;
    if (!canvas || !video || !video.videoWidth) return;
    const ctx = canvas.getContext("2d");
    const cw = canvas.width, ch = canvas.height, vw = video.videoWidth, vh = video.videoHeight;
    const scale = captureMode === "fill" ? Math.max(cw / vw, ch / vh) : Math.min(cw / vw, ch / vh);
    const dw = vw * scale, dh = vh * scale, dx = (cw - dw) / 2, dy = (ch - dh) / 2;
    ctx.fillStyle = "#000"; ctx.fillRect(0, 0, cw, ch); ctx.drawImage(video, dx, dy, dw, dh);
  }
  function drawCapture() { drawContain(canvasRef.current); drawContain(bigCanvasRef.current); }
  function addMark(e) {
    if (e.button !== 0) return;
    const rect = e.currentTarget.getBoundingClientRect();
    setMarks([...marks, { x: ((e.clientX - rect.left) / rect.width) * 100, y: ((e.clientY - rect.top) / rect.height) * 100, label: markLabel || "objetivo", time: nowIso() }]);
  }

  const chartData = (selected.snapshots || []).slice(-12).map((s, i) => ({ idx: i, fuel: s.resources?.fuel?.value || 0, rares: s.resources?.rares?.value || 0, electronics: s.resources?.electronics?.value || 0, components: s.resources?.components?.value || 0 }));
  const prodData = RESOURCE_KEYS.map(k => ({ name: RESOURCE_META[k].short, value: Number(selected.resources?.[k]?.hour || 0) }));

  return (
    <div className="app">
      <header className="topbar">
        <div><div className="eyebrow">CON War Room v0.9.4</div><h1>Live Tactical Command Center</h1></div>
        <div className="topActions"><span className={apiOk ? "pill good" : "pill danger"}>API {apiOk ? "ONLINE" : "OFFLINE"}</span><span className="pill">{clock.toLocaleTimeString()}</span><button className={live ? "good" : "warn"} onClick={() => setLive(!live)}><Zap size={16}/> {live ? "Live ON" : "Live OFF"}</button><button onClick={saveSnapshot}><Save size={16}/> Snapshot</button></div>
      </header>

      <aside className="sidebar">
        <Panel title="Partidas" right={games.length}>{games.map(g => <button key={g.id} className={`gameBtn ${g.id===selected.id ? "active" : ""}`} onClick={() => setSelectedId(g.id)}><strong>{g.name}</strong><span>{g.country} - Dia {g.day} - {readinessScore(g)}% ready</span></button>)}<div className="row"><button onClick={createGame}>Nueva</button><button className="danger" onClick={deleteGame}>Borrar</button></div></Panel>
        <Panel title="Tabs"><nav className="tabNav">{[["command","Command"],["movement","Movement"],["capture","Capture"],["sync","Sync"],["data","Data"]].map(([id,l]) => <button key={id} className={tab===id ? "active":""} onClick={() => setTab(id)}>{l}</button>)}</nav></Panel>
        <Panel title="Live Engine"><p className="hint">OCR queda experimental. Para avanzar rapido usa Sync: pega los 7 valores y aplica.</p></Panel>
      </aside>

      <main className="main">
        {tab === "command" && <CommandTab selected={selected} patchSelected={patchSelected} updateResource={updateResource} chartData={chartData} prodData={prodData} />}
        {tab === "movement" && <MovementTab selected={selected} patchSelected={patchSelected} askMovement={askMovement} movementPlan={movementPlan} />}
        {tab === "capture" && <CaptureTab videoRef={videoRef} canvasRef={canvasRef} bigCanvasRef={bigCanvasRef} captureOpen={captureOpen} setCaptureOpen={setCaptureOpen} captureStatus={captureStatus} captureMode={captureMode} setCaptureMode={setCaptureMode} captureSize={captureSize} setCaptureSize={setCaptureSize} startCapture={startCapture} stopCapture={stopCapture} addMark={addMark} marks={marks} setMarks={setMarks} markLabel={markLabel} setMarkLabel={setMarkLabel} />}
        {tab === "sync" && <SyncTab selected={selected} syncStock={syncStock} setSyncStock={setSyncStock} syncHour={syncHour} setSyncHour={setSyncHour} syncPreview={syncPreview} previewFastSync={previewFastSync} applyFastSync={applyFastSync} />}
        {tab === "data" && <DataTab selected={selected} patchSelected={patchSelected} games={games} persist={persist} />}
      </main>

      <aside className="rightbar">
        <Panel title="Threat Radar" right={`${(selected.fronts||[]).filter(f=>["high","critical"].includes(f.risk)).length} high risk`}><div className="radarBox"><span className="dot red"/><span className="dot amber"/><span className="dot cyan"/></div>{(selected.fronts||[]).map((f,i)=><Front key={i} f={f}/>)}</Panel>
        <Panel title="Assistant" right="advisor"><textarea className="advisor" value={advisor} onChange={e=>setAdvisor(e.target.value)}/><div className="row"><button onClick={askGeneral}><Bot size={16}/> Ask</button><button onClick={askMovement}><Crosshair size={16}/> Movement</button><button onClick={()=>navigator.clipboard.writeText(advisor)}>Copiar</button></div></Panel>
        <Panel title="Activity Feed">{(selected.feed||[]).slice().reverse().slice(0,10).map((x,i)=><div className="feedItem" key={i}><strong>{new Date(x.time).toLocaleTimeString()}</strong><p>{x.text}</p></div>)}</Panel>
      </aside>
    </div>
  );
}

function Panel({ title, right, children }) { return <section className="panel"><div className="panelTitle"><h2>{title}</h2>{right !== undefined && <span>{right}</span>}</div>{children}</section>; }
function Metric({ label, value, sub }) { return <div className="metricCard"><h3>{label}</h3><div className="metricValue">{value}</div><p className="hint">{sub}</p></div>; }
function CommandTab({ selected, patchSelected, updateResource, chartData, prodData }) {
  return <>
    <section className="metrics"><Metric label="Partida" value={selected.name} sub={selected.country}/><Metric label="Dia" value={selected.day} sub="ciclo operativo"/><Metric label="VP" value={selected.victory_points} sub="victory points"/><Metric label="Readiness" value={`${readinessScore(selected)}%`} sub="economia + frentes"/><Metric label="ETA Critico" value={criticalEta(selected)} sub="primer recurso bajo"/></section>
    <Panel title="Ficha de partida"><div className="formGrid four"><label>Nombre<input value={selected.name} onChange={e=>patchSelected({name:e.target.value})}/></label><label>Pais<input value={selected.country} onChange={e=>patchSelected({country:e.target.value})}/></label><label>Dia<input type="number" value={selected.day} onChange={e=>patchSelected({day:Number(e.target.value)})}/></label><label>VP<input value={selected.victory_points} onChange={e=>patchSelected({victory_points:e.target.value})}/></label></div></Panel>
    <Panel title="Economy Radar Live"><div className="resourceGrid">{RESOURCE_KEYS.map(k => <Resource key={k} kName={k} r={selected.resources[k]} onChange={(p,v)=>updateResource(k,p,v)}/>)}</div></Panel>
    <section className="chartGrid"><Panel title="Historico de stock"><ResponsiveContainer width="100%" height={230}><LineChart data={chartData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="idx" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:"#07111d",border:"1px solid #36d9ff",color:"#d8f3ff"}}/><Line dataKey="fuel" stroke="#ffcc66" strokeWidth={3}/><Line dataKey="rares" stroke="#bf7dff" strokeWidth={3}/><Line dataKey="electronics" stroke="#36d9ff" strokeWidth={3}/><Line dataKey="components" stroke="#3dff9b" strokeWidth={3}/></LineChart></ResponsiveContainer></Panel><Panel title="Produccion/hora"><ResponsiveContainer width="100%" height={230}><BarChart data={prodData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="name" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:"#07111d",border:"1px solid #36d9ff",color:"#d8f3ff"}}/><Bar dataKey="value" fill="#36d9ff"/></BarChart></ResponsiveContainer></Panel></section>
  </>;
}
function Resource({ kName, r, onChange }) {
  const meta = RESOURCE_META[kName];
  return <div className={`resourceCard ${r.status}`}><div className="resourceTop"><strong><img className="resImage" src={meta.img} alt={meta.label}/>{meta.label}</strong><em>{r.status}</em></div><div className="formGrid three"><label>Stock<input type="number" value={Math.round(Number(r.value||0))} onChange={e=>onChange("value",e.target.value)}/></label><label>Hora<input type="number" value={r.hour} onChange={e=>onChange("hour",e.target.value)}/></label><label>Status<select value={r.status} onChange={e=>onChange("status",e.target.value)}><option>stable</option><option>low</option><option>critical</option></select></label></div><div className="bar"><i style={{width:`${Math.max(4,Math.min(100,Number(r.value||0)/meta.target*100))}%`}}/></div><p className="hint">target tactico: {meta.target}</p></div>;
}
function SyncTab({ selected, syncStock, setSyncStock, syncHour, setSyncHour, syncPreview, previewFastSync, applyFastSync }) {
  return <section className="syncGrid"><Panel title="Fast Resource Sync"><p className="hint">Pega los recursos de izquierda a derecha. Formato rapido: 7 stocks y 7 producciones. Tambien acepta 14 numeros intercalados: stock hora stock hora...</p><div className="formGrid two"><label>Stocks<textarea value={syncStock} onChange={e=>setSyncStock(e.target.value)} placeholder="1857 2704 928 481 217 1206 13764"/></label><label>Produccion / hora<textarea value={syncHour} onChange={e=>setSyncHour(e.target.value)} placeholder="119 69 64 60 43 49 485"/></label></div><div className="row"><button onClick={previewFastSync}>Preview</button><button onClick={applyFastSync}>Aplicar Sync</button></div><textarea className="advisor small" value={syncPreview} readOnly/></Panel><Panel title="Orden actual">{RESOURCE_KEYS.map(k => <div className="syncResource" key={k}><img src={RESOURCE_META[k].img}/><strong>{RESOURCE_META[k].label}</strong><span>{Math.round(selected.resources[k]?.value || 0)}</span><em>+{selected.resources[k]?.hour || 0}/h</em></div>)}</Panel></section>;
}
function MovementTab({ selected, patchSelected, askMovement, movementPlan }) {
  const [stacks, setStacks] = useState(JSON.stringify(selected.stacks||[], null, 2));
  const [enemy, setEnemy] = useState(JSON.stringify(selected.enemy||[], null, 2));
  useEffect(()=>{setStacks(JSON.stringify(selected.stacks||[], null, 2)); setEnemy(JSON.stringify(selected.enemy||[], null, 2));}, [selected.id]);
  function save(){ patchSelected({ stacks: JSON.parse(stacks), enemy: JSON.parse(enemy) }); }
  return <section className="movementGrid"><Panel title="Movement Assistant"><p className="hint">No ejecuta acciones. Recomienda movimientos, contramedidas y que NO mover. Funciona local aunque la API este offline.</p><div className="formGrid two"><label>Stacks propios JSON<textarea value={stacks} onChange={e=>setStacks(e.target.value)}/></label><label>Enemigos observados JSON<textarea value={enemy} onChange={e=>setEnemy(e.target.value)}/></label></div><div className="row"><button onClick={save}><Save size={16}/> Guardar</button><button onClick={askMovement}><Target size={16}/> Recomendar movimiento</button></div></Panel><Panel title="Plan de movimiento"><textarea className="advisor" value={movementPlan} readOnly/></Panel><section className="moveCols"><Panel title="Stacks propios">{(selected.stacks||[]).map((s,i)=><MoveCard key={i} item={s}/>)}</Panel><Panel title="Contramedidas">{(selected.enemy||[]).map((e,i)=><MoveCard key={i} item={e}/>)}</Panel></section></section>;
}
function MoveCard({ item }) { return <div className="moveCard"><strong>{item.name || item.location}</strong>{Object.entries(item).map(([k,v])=><p key={k}><b>{k}:</b> {String(v)}</p>)}</div>; }
function CaptureTab({ videoRef, canvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, captureSize, setCaptureSize, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel }) {
  return <section className="capturePage"><Panel title="Capture Center" right={captureStatus}><video ref={videoRef} className="hiddenVideo"/><div className={`captureStage ${captureSize}`} onClick={addMark}><canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/>{marks.map((m,i)=><div className="captureMark" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}</div><div className="row"><input className="markInput" value={markLabel} onChange={e=>setMarkLabel(e.target.value)} placeholder="texto del marcador"/><button onClick={startCapture}><Video size={16}/> Conectar pantalla</button><button onClick={()=>setCaptureOpen(true)}><Eye size={16}/> Ampliar</button><button onClick={()=>setCaptureSize(captureSize==="compact"?"large":"compact")}>Tamano {captureSize}</button><button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button><button onClick={()=>setMarks([])}>Limpiar marcas</button><button className="danger" onClick={stopCapture}>Parar</button></div><p className="hint">Click crea marcador tactico. Captura observa, no controla el juego.</p></Panel>{captureOpen && <div className="captureModal"><div className="captureModalTop"><strong>LIVE GAME FEED</strong><div className="row"><button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button><button className="danger" onClick={()=>setCaptureOpen(false)}>Cerrar</button></div></div><div className="captureBigStage" onClick={addMark}><canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig"/>{marks.map((m,i)=><div className="captureMark big" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}</div></div>}</section>;
}
function DataTab({ selected, patchSelected, games, persist }) {
  const [fronts,setFronts]=useState(JSON.stringify(selected.fronts||[],null,2)); const [research,setResearch]=useState((selected.research||[]).join(", ")); const [notes,setNotes]=useState(selected.notes||""); const [io,setIo]=useState("");
  useEffect(()=>{setFronts(JSON.stringify(selected.fronts||[],null,2));setResearch((selected.research||[]).join(", "));setNotes(selected.notes||"");},[selected.id]);
  function save(){patchSelected({fronts:JSON.parse(fronts),research:research.split(",").map(x=>x.trim()).filter(Boolean),notes});}
  return <section className="dataGrid"><Panel title="Datos de partida"><div className="formGrid three"><label>Frentes JSON<textarea value={fronts} onChange={e=>setFronts(e.target.value)}/></label><label>Research<textarea value={research} onChange={e=>setResearch(e.target.value)}/></label><label>Notas<textarea value={notes} onChange={e=>setNotes(e.target.value)}/></label></div><button onClick={save}>Guardar datos</button></Panel><Panel title="Import / Export JSON"><textarea value={io} onChange={e=>setIo(e.target.value)}/><div className="row"><button onClick={()=>setIo(JSON.stringify(games,null,2))}>Exportar</button><button onClick={()=>{const p=JSON.parse(io).map(normalizeGame); persist(p);}}>Importar</button></div></Panel></section>;
}
function Front({ f }) { return <div className="frontItem"><strong>{f.name}</strong><p>{f.state} - {f.action}</p><span>{f.risk}</span></div>; }

createRoot(document.getElementById("root")).render(<App/>);
'@
[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $mainJsx, $Utf8NoBom)

$css = @'
:root{--bg:#02050b;--panel:rgba(7,18,30,.92);--cyan:#36d9ff;--green:#3dff9b;--red:#ff4d5f;--amber:#ffcc66;--purple:#bf7dff;--text:#d8f3ff;--muted:#8fb4c7;--border:rgba(54,217,255,.25)}
*{box-sizing:border-box}html,body,#root{min-height:100%;margin:0}body{background:radial-gradient(circle at 12% 10%,rgba(54,217,255,.14),transparent 28%),radial-gradient(circle at 80% 2%,rgba(61,255,155,.1),transparent 24%),linear-gradient(135deg,#010309,#07111d 50%,#010208);color:var(--text);font-family:Inter,Segoe UI,Arial,sans-serif}body:before{content:"";position:fixed;inset:0;pointer-events:none;background-image:linear-gradient(rgba(54,217,255,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(54,217,255,.045) 1px,transparent 1px);background-size:42px 42px;mask-image:radial-gradient(circle at center,black 0%,transparent 82%)}
button,input,textarea,select{font:inherit}button{display:inline-flex;align-items:center;justify-content:center;gap:8px;border:1px solid var(--cyan);background:rgba(54,217,255,.11);color:var(--cyan);padding:10px 13px;border-radius:12px;font-weight:900;text-transform:uppercase;letter-spacing:.8px;cursor:pointer}button:hover{background:rgba(54,217,255,.22);box-shadow:0 0 18px rgba(54,217,255,.22)}button.danger{border-color:var(--red);color:var(--red);background:rgba(255,77,95,.08)}button.good{border-color:var(--green);color:var(--green)}button.warn{border-color:var(--amber);color:var(--amber)}
input,textarea,select{width:100%;background:rgba(0,0,0,.32);border:1px solid rgba(54,217,255,.24);border-radius:12px;color:var(--text);padding:10px 12px;outline:none}textarea{min-height:150px;font-family:Consolas,monospace;font-size:12px}label{display:block;color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:1px}label input,label textarea,label select{margin-top:6px}
.app{display:grid;grid-template-columns:300px minmax(760px,1fr)430px;grid-template-rows:auto 1fr;gap:16px;padding:18px;position:relative;z-index:1}.topbar{grid-column:1/-1;display:flex;justify-content:space-between;gap:18px;align-items:center}.eyebrow{color:var(--muted);letter-spacing:3px;text-transform:uppercase;font-size:12px}h1{margin:6px 0 0;font-size:34px;letter-spacing:2px;text-transform:uppercase;text-shadow:0 0 22px rgba(54,217,255,.55)}.topActions,.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.pill{border:1px solid var(--border);border-radius:999px;padding:9px 13px;font-weight:900;background:rgba(54,217,255,.08)}.pill.good{color:var(--green)}.pill.danger{color:var(--red)}
.sidebar,.main,.rightbar{display:flex;flex-direction:column;gap:14px}.panel,.metricCard{border:1px solid var(--border);background:linear-gradient(180deg,var(--panel),rgba(3,9,16,.93));border-radius:18px;padding:15px;box-shadow:0 18px 60px rgba(0,0,0,.36),inset 0 0 24px rgba(54,217,255,.035);backdrop-filter:blur(8px)}.panelTitle{display:flex;justify-content:space-between;gap:10px;margin-bottom:12px;color:var(--muted)}.panelTitle h2{margin:0;display:flex;align-items:center;gap:8px;font-size:13px;text-transform:uppercase;letter-spacing:1.5px}.panelTitle span{font-size:12px}
.gameBtn{text-align:left;display:block;width:100%;background:rgba(255,255,255,.035);border-color:rgba(255,255,255,.08);color:var(--text);margin-bottom:10px}.gameBtn.active{border-color:var(--cyan);background:rgba(54,217,255,.14);box-shadow:0 0 24px rgba(54,217,255,.16)}.gameBtn strong{display:block}.gameBtn span{display:block;color:var(--muted);font-size:12px;margin-top:5px}.tabNav{display:grid;grid-template-columns:1fr 1fr;gap:8px}.tabNav button.active{background:rgba(54,217,255,.24)}
.metrics{display:grid;grid-template-columns:repeat(5,1fr);gap:10px}.metricCard h3{margin:0 0 8px;color:var(--muted);letter-spacing:1.5px;text-transform:uppercase;font-size:12px}.metricValue{font-size:26px;font-weight:950;line-height:1}.hint{color:var(--muted);font-size:12px;margin:8px 0 0;line-height:1.45}.formGrid{display:grid;gap:10px;margin-bottom:10px}.formGrid.two{grid-template-columns:1fr 1fr}.formGrid.three{grid-template-columns:repeat(3,1fr)}.formGrid.four{grid-template-columns:repeat(4,1fr)}
.resourceGrid{display:grid;grid-template-columns:repeat(2,minmax(330px,1fr));gap:10px}.resourceCard{border:1px solid rgba(255,255,255,.08);border-left:3px solid var(--cyan);background:rgba(255,255,255,.035);border-radius:16px;padding:13px;min-height:180px}.resourceCard.critical{border-left-color:var(--red)}.resourceCard.low{border-left-color:var(--amber)}.resourceCard.stable{border-left-color:var(--green)}.resourceTop{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}.resourceTop strong{display:flex;align-items:center;gap:12px;text-transform:uppercase;font-size:15px;color:#d8f3ff}.resourceTop em{font-style:normal;color:var(--red)}.stable .resourceTop em{color:var(--green)}.low .resourceTop em{color:var(--amber)}.resImage{width:58px;height:58px;object-fit:contain;border-radius:14px;border:1px solid rgba(54,217,255,.3);background:rgba(54,217,255,.08);box-shadow:0 0 16px rgba(54,217,255,.22);padding:4px}.bar{height:6px;background:rgba(255,255,255,.08);border-radius:999px;overflow:hidden}.bar i{display:block;height:100%;background:linear-gradient(90deg,var(--cyan),var(--green))}
.chartGrid{display:grid;grid-template-columns:1fr 1fr;gap:14px}.radarBox{height:250px;border-radius:50%;position:relative;margin:0 auto 12px;max-width:250px;border:1px solid rgba(54,217,255,.35);background:radial-gradient(circle,transparent 0 22%,rgba(54,217,255,.08) 23% 24%,transparent 25% 46%,rgba(54,217,255,.08) 47% 48%,transparent 49%),conic-gradient(from 35deg,rgba(61,255,155,.3),transparent 25%,transparent)}.dot{position:absolute;width:8px;height:8px;border-radius:50%;left:60%;top:20%;background:var(--red);box-shadow:0 0 15px var(--red)}.dot.amber{left:25%;top:70%;background:var(--amber);box-shadow:0 0 15px var(--amber)}.dot.cyan{left:70%;top:62%;background:var(--cyan);box-shadow:0 0 15px var(--cyan)}
.frontItem,.feedItem,.moveCard{border-left:3px solid var(--cyan);background:rgba(54,217,255,.055);border-radius:12px;padding:10px;margin-bottom:8px}.frontItem p,.feedItem p,.moveCard p{margin:5px 0;color:var(--muted);font-size:12px}.frontItem span{font-size:11px;border:1px solid var(--border);border-radius:999px;padding:4px 8px;color:var(--cyan)}.advisor{min-height:310px;color:var(--green)}.advisor.small{min-height:180px}.movementGrid,.dataGrid,.capturePage,.syncGrid{display:flex;flex-direction:column;gap:14px}.moveCols{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.hiddenVideo{display:none}.captureStage,.captureBigStage{position:relative;width:100%;background:#000;border-radius:18px;overflow:hidden;border:1px solid rgba(54,217,255,.25);cursor:crosshair}.captureCanvas{width:100%;background:#000;display:block}.captureStage.compact .captureCanvas{height:380px}.captureStage.large .captureCanvas{height:620px}.captureBig{width:100%;height:100%;background:#000;display:block}.captureMark{position:absolute;transform:translate(-50%,-50%);display:flex;align-items:center;gap:7px;pointer-events:none;filter:drop-shadow(0 0 8px rgba(61,255,155,.65))}.captureMark span{width:28px;height:28px;border-radius:999px;background:rgba(61,255,155,.18);border:1px solid #3dff9b;color:#3dff9b;display:inline-flex;align-items:center;justify-content:center;font-weight:950}.captureMark em{font-style:normal;font-size:12px;color:#d8f3ff;background:rgba(0,0,0,.72);border:1px solid rgba(54,217,255,.35);border-radius:999px;padding:5px 8px}.captureMark.big span{width:34px;height:34px}.captureMark.big em{font-size:14px}.markInput{max-width:220px}.captureModal{position:fixed;z-index:9999;inset:0;background:rgba(0,0,0,.92);display:grid;grid-template-rows:auto 1fr;padding:20px;gap:12px}.captureModalTop{display:flex;justify-content:space-between;align-items:center;border:1px solid var(--border);background:rgba(7,18,30,.92);border-radius:16px;padding:12px}
.syncGrid{display:grid;grid-template-columns:1.2fr .8fr;gap:14px}.syncResource{display:grid;grid-template-columns:50px 1fr auto auto;align-items:center;gap:10px;border:1px solid rgba(54,217,255,.18);border-radius:12px;padding:8px;margin-bottom:8px;background:rgba(54,217,255,.045)}.syncResource img{width:42px;height:42px}.syncResource strong{text-transform:uppercase}.syncResource span{font-weight:900;color:#d8f3ff}.syncResource em{font-style:normal;color:#3dff9b}
@media(max-width:1400px){.app{grid-template-columns:280px 1fr}.rightbar{grid-column:1/-1}.metrics{grid-template-columns:repeat(3,1fr)}.syncGrid{grid-template-columns:1fr}}@media(max-width:900px){.app,.metrics,.resourceGrid,.chartGrid,.formGrid.two,.formGrid.three,.formGrid.four,.moveCols{grid-template-columns:1fr}.topbar{align-items:flex-start;flex-direction:column}}
'@
[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)

Write-Host "v0.9.4 Practical Sync + Movement aplicado."
Write-Host "Siguiente: git add . ; git commit ; git push ; build web ; rollout restart."
