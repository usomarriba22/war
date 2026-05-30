# CON War Room v0.8 — React Command Center + Movement Advisor
# Ejecutar desde VS Code PowerShell.
# Ruta esperada del repo: C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"

Write-Host "== CON War Room v0.8 React Command Center ==" -ForegroundColor Cyan
Write-Host "Repo: $(Get-Location)" -ForegroundColor Cyan

# Backup del frontend anterior
if (Test-Path ".\02-apps\warroom-web\public\index.html") {
  New-Item -ItemType Directory -Force -Path ".\02-apps\warroom-web\_legacy" | Out-Null
  Copy-Item ".\02-apps\warroom-web\public\index.html" ".\02-apps\warroom-web\_legacy\index-legacy-before-react.html" -Force
}

# Rehacer warroom-web como app Vite/React limpia
Remove-Item ".\02-apps\warroom-web\public" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ".\02-apps\warroom-web\src" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ".\02-apps\warroom-web\index.html" -Force -ErrorAction SilentlyContinue
Remove-Item ".\02-apps\warroom-web\package.json" -Force -ErrorAction SilentlyContinue
Remove-Item ".\02-apps\warroom-web\nginx.conf" -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path `
  ".\02-apps\warroom-web\src", `
  ".\02-apps\warroom-web\src\lib", `
  ".\02-apps\warroom-web\public" | Out-Null

@'
{
  "name": "con-warroom-web",
  "version": "0.8.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0 --port 3000",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0 --port 3000"
  },
  "dependencies": {
    "@vitejs/plugin-react": "latest",
    "vite": "latest",
    "react": "latest",
    "react-dom": "latest",
    "lucide-react": "latest",
    "recharts": "latest"
  },
  "devDependencies": {}
}
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\package.json"

@'
<!doctype html>
<html lang="es">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>CON War Room v0.8</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\index.html"

@'
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\Dockerfile"

@'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\nginx.conf"

@'
export const RESOURCE_META = {
  supplies: { label: "Supplies", icon: "📦", target: 5000 },
  components: { label: "Components", icon: "⚙️", target: 4500 },
  fuel: { label: "Fuel", icon: "⛽", target: 3500 },
  electronics: { label: "Electronics", icon: "🔌", target: 2500 },
  rares: { label: "Rares", icon: "💎", target: 1800 },
  manpower: { label: "Manpower", icon: "🪖", target: 3000 },
  money: { label: "Money", icon: "💵", target: 20000 }
};

export const STORAGE_KEY = "con-war-room-games-v08";
export const API_BASE = "http://127.0.0.1:8000";

export function baseGame(id, name, country) {
  return {
    id,
    name,
    country,
    day: 1,
    victory_points: "0 / 5920",
    phase: "early expansion",
    coalition: [],
    resources: {
      supplies: { value: 0, hour: 0, status: "critical" },
      components: { value: 0, hour: 0, status: "critical" },
      fuel: { value: 0, hour: 0, status: "critical" },
      electronics: { value: 0, hour: 0, status: "critical" },
      rares: { value: 0, hour: 0, status: "critical" },
      manpower: { value: 0, hour: 0, status: "critical" },
      money: { value: 0, hour: 0, status: "critical" }
    },
    fronts: [
      { name: "Frente 1", state: "pendiente", risk: "medium", action: "actualizar" }
    ],
    stacks: [
      {
        name: "Stack principal",
        location: "capital / frente",
        units: "infanteria, recon",
        mission: "defensa",
        condition: "100%",
        threat: "medium",
        notes: "actualizar manualmente"
      }
    ],
    enemy: [
      {
        location: "frente enemigo",
        observed: "infanteria / desconocido",
        risk: "medium",
        counter: "recon + artilleria + cobertura aerea"
      }
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
  g.day = 2;
  g.victory_points = "432 / 5920";
  g.coalition = ["Venezuela", "USA", "Canada", "Bolivia"];
  g.resources = {
    supplies: { value: 7079, hour: 91, status: "stable" },
    components: { value: 5474, hour: 45, status: "stable" },
    fuel: { value: 345, hour: 50, status: "critical" },
    electronics: { value: 719, hour: 49, status: "low" },
    rares: { value: 84, hour: 34, status: "critical" },
    manpower: { value: 3557, hour: 48, status: "stable" },
    money: { value: 32968, hour: 382, status: "stable" }
  };
  g.fronts = [
    { name: "Panama", state: "ocupado", risk: "medium", action: "mantener guarnicion" },
    { name: "Ecuador / Quito", state: "ofensiva activa", risk: "high", action: "cerrar y estabilizar" },
    { name: "Peru", state: "siguiente objetivo posible", risk: "medium", action: "no atacar aun" },
    { name: "Caribe", state: "vigilancia naval", risk: "medium", action: "preparar fragatas" }
  ];
  g.stacks = [
    { name: "Grupo Quito", location: "Ecuador/Quito", units: "infanteria + recon", mission: "tomar capital", condition: "70%", threat: "high", notes: "no sobreextender" },
    { name: "Guarnicion Panama", location: "Panama", units: "infanteria", mission: "control urbano", condition: "100%", threat: "medium", notes: "evitar insurgencia" }
  ];
  g.enemy = [
    { location: "Quito", observed: "defensa urbana probable", risk: "high", counter: "rodear, esperar organizacion, no entrar con unidades danadas" },
    { location: "Caribe", observed: "naval desconocido", risk: "medium", counter: "radar + fragatas; no enviar transporte solo" }
  ];
  g.research = ["Radar movil", "Antiaereo movil/SAM", "Fragata", "Railgun", "Satelite", "Submarino elite"];
  return [
    g,
    baseGame("slot-2", "Partida 2", "Pendiente"),
    baseGame("slot-3", "Partida 3", "Pendiente"),
    baseGame("slot-4", "Partida 4", "Pendiente")
  ];
}

export function deriveStatus(key, value) {
  const target = RESOURCE_META[key]?.target || 1000;
  if (Number(value || 0) < target * 0.25) return "critical";
  if (Number(value || 0) < target * 0.55) return "low";
  return "stable";
}

export function readinessScore(game) {
  let score = 100;
  Object.values(game.resources || {}).forEach((r) => {
    if (r.status === "critical") score -= 12;
    if (r.status === "low") score -= 6;
  });
  (game.fronts || []).forEach((f) => {
    if (f.risk === "critical") score -= 18;
    if (f.risk === "high") score -= 10;
    if (f.risk === "medium") score -= 4;
  });
  return Math.max(0, Math.min(100, score));
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
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\src\lib\data.js"

@'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Activity, Bot, Brain, Crosshair, Eye, Gauge, Map, Radar, Save, ShieldAlert, Swords, Video, Zap } from "lucide-react";
import { BarChart, Bar, CartesianGrid, LineChart, Line, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { API_BASE, RESOURCE_META, STORAGE_KEY, baseGame, seedGames, deriveStatus, normalizeGame, readinessScore } from "./lib/data";
import "./styles.css";

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
function nowIso() { return new Date().toISOString(); }
function addFeed(game, text, level = "info") {
  const feed = [...(game.feed || []), { time: nowIso(), text, level }];
  return { ...game, feed: feed.slice(-80), updated_at: nowIso() };
}
function applyLiveTick(game, live) {
  if (!live) return game;
  const last = new Date(game.live_base_at || game.updated_at || nowIso()).getTime();
  const diffSeconds = Math.max(0, (Date.now() - last) / 1000);
  if (diffSeconds < 1) return game;
  const resources = { ...game.resources };
  Object.entries(resources).forEach(([key, r]) => {
    const inc = Number(r.hour || 0) * diffSeconds / 3600;
    const value = Math.round((Number(r.value || 0) + inc) * 100) / 100;
    resources[key] = { ...r, value, status: deriveStatus(key, value) };
  });
  return { ...game, resources, live_base_at: nowIso() };
}
function buildSnapshot(game) {
  return {
    time: nowIso(), day: game.day, victory_points: game.victory_points,
    resources: JSON.parse(JSON.stringify(game.resources)),
    fronts: JSON.parse(JSON.stringify(game.fronts || [])),
    stacks: JSON.parse(JSON.stringify(game.stacks || [])),
    enemy: JSON.parse(JSON.stringify(game.enemy || [])),
    readiness: readinessScore(game)
  };
}
function getCriticalEta(game) {
  const low = Object.entries(game.resources || {}).find(([, r]) => r.status === "critical" || r.status === "low");
  return low ? `${RESOURCE_META[low[0]]?.label || low[0]} bajo` : "OK";
}

function App() {
  const [games, setGames] = useState(readGames);
  const [selectedId, setSelectedId] = useState(() => readGames()[0]?.id);
  const [apiOk, setApiOk] = useState(false);
  const [live, setLive] = useState(true);
  const [advisor, setAdvisor] = useState("Selecciona una partida y pulsa Ask Advisor.");
  const [activeTab, setActiveTab] = useState("command");
  const [clock, setClock] = useState(new Date());
  const [captureOpen, setCaptureOpen] = useState(false);
  const [captureMode, setCaptureMode] = useState("fit");
  const [captureStatus, setCaptureStatus] = useState("offline");
  const videoRef = useRef(null);
  const previewCanvasRef = useRef(null);
  const bigCanvasRef = useRef(null);
  const streamRef = useRef(null);
  const drawTimerRef = useRef(null);

  const selected = useMemo(() => games.find((g) => g.id === selectedId) || games[0], [games, selectedId]);
  function persist(nextGames) { setGames(nextGames); writeGames(nextGames); }
  function replaceSelected(nextGame) { persist(games.map((g) => (g.id === nextGame.id ? { ...nextGame, updated_at: nowIso() } : g))); }
  function patchSelected(patch) { replaceSelected({ ...selected, ...patch }); }

  useEffect(() => {
    const t = setInterval(async () => {
      setClock(new Date());
      try { const res = await fetch(`${API_BASE}/health`, { cache: "no-store" }); setApiOk(res.ok); } catch { setApiOk(false); }
      setGames((old) => { const next = old.map((g) => applyLiveTick(g, live)); writeGames(next); return next; });
    }, 1000);
    return () => clearInterval(t);
  }, [live]);

  function createGame() { const g = baseGame(`game-${Date.now()}`, "Nueva partida", "Pais"); persist([...games, g]); setSelectedId(g.id); }
  function deleteGame() { if (games.length <= 1) return alert("Debe quedar al menos una partida."); if (!confirm(`Borrar ${selected.name}?`)) return; const next = games.filter((g) => g.id !== selected.id); persist(next); setSelectedId(next[0].id); }
  function updateResource(key, prop, value) {
    const r = selected.resources[key] || {};
    const nextValue = prop === "value" || prop === "hour" ? Number(value) : value;
    const nextR = { ...r, [prop]: nextValue };
    if (prop !== "status") nextR.status = deriveStatus(key, prop === "value" ? nextValue : nextR.value);
    patchSelected({ resources: { ...selected.resources, [key]: nextR }, live_base_at: nowIso() });
  }
  function saveSnapshot() { const snap = buildSnapshot(selected); replaceSelected(addFeed({ ...selected, snapshots: [...(selected.snapshots || []), snap] }, "Snapshot manual guardado", "info")); }
  async function askAdvisor(mode = "general") {
    const question = mode === "movement"
      ? "Dame recomendaciones de movimiento sin ejecutar acciones. Analiza stacks propios, enemigos, frentes, riesgos, contraataques, posicionamiento, defensa y que NO mover."
      : "Analiza esta partida y dime que hacer en las proximas 6-12 horas. Prioriza economia, investigacion, expansion, defensa y elites.";
    try {
      const res = await fetch(`${API_BASE}/api/advisor/analyze`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ game_state: selected, question }) });
      const data = await res.json();
      setAdvisor(data.answer || JSON.stringify(data, null, 2));
      replaceSelected(addFeed(selected, mode === "movement" ? "Movement Advisor generado" : "Advisor generado", "info"));
    } catch (e) { setAdvisor(`Error llamando advisor: ${e.message}`); }
  }
  function exportJson() { navigator.clipboard.writeText(JSON.stringify(games, null, 2)); replaceSelected(addFeed(selected, "JSON copiado", "info")); }
  function importJson(text) { const parsed = JSON.parse(text); if (!Array.isArray(parsed)) throw new Error("El JSON debe ser array de partidas"); const next = parsed.map(normalizeGame); persist(next); setSelectedId(next[0]?.id); }

  async function startCapture() {
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: { ideal: 30, max: 60 }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false });
      streamRef.current = stream;
      const video = videoRef.current;
      video.srcObject = stream; video.muted = true; video.playsInline = true; await video.play();
      setCaptureStatus("capturing");
      drawTimerRef.current = setInterval(drawCapture, 1000 / 30);
      stream.getVideoTracks()[0].onended = stopCapture;
    } catch (e) { setCaptureStatus(`denied: ${e.message}`); }
  }
  function stopCapture() { if (streamRef.current) streamRef.current.getTracks().forEach((t) => t.stop()); streamRef.current = null; if (drawTimerRef.current) clearInterval(drawTimerRef.current); drawTimerRef.current = null; setCaptureStatus("offline"); }
  function drawToCanvas(canvas) {
    const video = videoRef.current; if (!canvas || !video || !video.videoWidth) return;
    const ctx = canvas.getContext("2d"); const cw = canvas.width; const ch = canvas.height; const vw = video.videoWidth; const vh = video.videoHeight;
    const scale = captureMode === "fill" ? Math.max(cw / vw, ch / vh) : Math.min(cw / vw, ch / vh);
    const dw = vw * scale; const dh = vh * scale; const dx = (cw - dw) / 2; const dy = (ch - dh) / 2;
    ctx.fillStyle = "#000"; ctx.fillRect(0, 0, cw, ch); ctx.drawImage(video, dx, dy, dw, dh);
  }
  function drawCapture() { drawToCanvas(previewCanvasRef.current); drawToCanvas(bigCanvasRef.current); }

  const chartData = (selected?.snapshots || []).slice(-12).map((s, idx) => ({ idx, fuel: Math.round(s.resources?.fuel?.value || 0), rares: Math.round(s.resources?.rares?.value || 0), electronics: Math.round(s.resources?.electronics?.value || 0), components: Math.round(s.resources?.components?.value || 0) }));
  const prodData = Object.entries(RESOURCE_META).map(([key, meta]) => ({ name: meta.label, value: Number(selected?.resources?.[key]?.hour || 0) }));
  if (!selected) return <div className="app">Sin partidas</div>;

  return <div className="app">
    <header className="topbar"><div><div className="eyebrow">CON War Room v0.8</div><h1>Live Tactical Command Center</h1></div><div className="topActions"><span className={apiOk ? "pill good" : "pill danger"}>API {apiOk ? "ONLINE" : "OFFLINE"}</span><span className="pill">{clock.toLocaleTimeString()}</span><button onClick={() => setLive(!live)} className={live ? "good" : "warn"}>{live ? "Live ON" : "Live OFF"}</button><button onClick={saveSnapshot}><Save size={16}/> Snapshot</button></div></header>
    <aside className="sidebar"><Panel title="Partidas" right={`${games.length}`}><div className="gameList">{games.map((g) => <button key={g.id} className={`gameBtn ${g.id === selected.id ? "active" : ""}`} onClick={() => setSelectedId(g.id)}><strong>{g.name}</strong><span>{g.country} - Dia {g.day} - {readinessScore(g)}% ready</span></button>)}</div><div className="row"><button onClick={createGame}>Nueva</button><button onClick={deleteGame} className="danger">Borrar</button></div></Panel><Panel title="Live Engine" icon={<Zap size={16}/>}><p className="hint">Stock = valor manual + produccion/hora proporcional al tiempo.</p></Panel><Panel title="Tabs" icon={<Gauge size={16}/>}><nav className="tabNav">{[["command","Command"],["movement","Movement"],["capture","Capture"],["data","Data"]].map(([id,label]) => <button key={id} className={activeTab === id ? "active" : ""} onClick={()=>setActiveTab(id)}>{label}</button>)}</nav></Panel></aside>
    <main className="main">{activeTab === "command" && <CommandTab selected={selected} patchSelected={patchSelected} updateResource={updateResource} chartData={chartData} prodData={prodData}/>} {activeTab === "movement" && <MovementTab selected={selected} patchSelected={patchSelected} askMovement={()=>askAdvisor("movement")}/>} {activeTab === "capture" && <CaptureTab videoRef={videoRef} previewCanvasRef={previewCanvasRef} bigCanvasRef={bigCanvasRef} captureOpen={captureOpen} setCaptureOpen={setCaptureOpen} captureStatus={captureStatus} captureMode={captureMode} setCaptureMode={setCaptureMode} startCapture={startCapture} stopCapture={stopCapture} drawCapture={drawCapture}/>} {activeTab === "data" && <DataTab selected={selected} patchSelected={patchSelected} games={games} exportJson={exportJson} importJson={importJson}/>}</main>
    <aside className="rightbar"><Panel title="Threat Radar" right={`${(selected.fronts||[]).filter(f=>["high","critical"].includes(f.risk)).length} high risk`} icon={<Radar size={16}/>}><div className="radarBox"><span className="radarDot red"></span><span className="radarDot amber"></span><span className="radarDot cyan"></span></div>{(selected.fronts||[]).map((f,i)=><FrontItem key={i} f={f}/>)}</Panel><Panel title="Assistant" right="advisor" icon={<Brain size={16}/>}><textarea className="advisor" value={advisor} onChange={(e)=>setAdvisor(e.target.value)} /><div className="row"><button onClick={()=>askAdvisor("general")}><Bot size={16}/> Ask</button><button onClick={()=>askAdvisor("movement")}><Crosshair size={16}/> Movement</button><button onClick={()=>navigator.clipboard.writeText(advisor)}>Copiar</button></div></Panel><Panel title="Activity Feed" icon={<Activity size={16}/>}><div className="feed">{(selected.feed||[]).slice().reverse().slice(0,12).map((item,i)=><div className={`feedItem ${item.level||""}`} key={i}><strong>{new Date(item.time).toLocaleTimeString()}</strong><p>{item.text}</p></div>)}</div></Panel></aside>
  </div>;
}

function Panel({ title, right, icon, children }) { return <section className="panel"><div className="panelTitle"><h2>{icon}{title}</h2>{right && <span>{right}</span>}</div>{children}</section>; }
function Metric({ label, value, sub }) { return <div className="metricCard"><h3>{label}</h3><div className="metricValue">{value}</div><div className="hint">{sub}</div></div>; }
function ResourceCard({ meta, r, onChange }) { return <div className={`resourceCard ${r.status}`}><div className="resourceTop"><strong><span>{meta.icon}</span>{meta.label}</strong><em>{r.status}</em></div><div className="formGrid three"><label>Stock<input type="number" value={Math.round(Number(r.value||0))} onChange={(e)=>onChange("value", e.target.value)}/></label><label>Hora<input type="number" value={r.hour} onChange={(e)=>onChange("hour", e.target.value)}/></label><label>Status<select value={r.status} onChange={(e)=>onChange("status", e.target.value)}><option>stable</option><option>low</option><option>critical</option></select></label></div><div className="bar"><i style={{width:`${Math.max(4,Math.min(100,Number(r.value||0)/meta.target*100))}%`}} /></div><p className="hint">target tactico: {meta.target}</p></div>; }
function FrontItem({ f }) { return <div className="frontItem"><strong>{f.name}</strong><p>{f.state} - {f.action}</p><span>{f.risk}</span></div>; }
function CommandTab({ selected, patchSelected, updateResource, chartData, prodData }) { return <><section className="metrics"><Metric label="Partida" value={selected.name} sub={selected.country}/><Metric label="Dia" value={selected.day} sub="ciclo operativo"/><Metric label="VP" value={selected.victory_points} sub="victory points"/><Metric label="Readiness" value={`${readinessScore(selected)}%`} sub="economia + frentes"/><Metric label="ETA Critico" value={getCriticalEta(selected)} sub="primer recurso bajo"/></section><Panel title="Ficha de partida"><div className="formGrid four"><label>Nombre<input value={selected.name} onChange={(e)=>patchSelected({name:e.target.value})}/></label><label>Pais<input value={selected.country} onChange={(e)=>patchSelected({country:e.target.value})}/></label><label>Dia<input type="number" value={selected.day} onChange={(e)=>patchSelected({day:Number(e.target.value)})}/></label><label>VP<input value={selected.victory_points} onChange={(e)=>patchSelected({victory_points:e.target.value})}/></label></div></Panel><Panel title="Economy Radar Live"><div className="resourceGrid">{Object.entries(RESOURCE_META).map(([key,meta])=><ResourceCard key={key} meta={meta} r={selected.resources[key]} onChange={(prop,value)=>updateResource(key,prop,value)}/>)}</div></Panel><section className="chartGrid"><Panel title="Historico de stock"><ResponsiveContainer width="100%" height={230}><LineChart data={chartData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="idx" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:'#07111d',border:'1px solid #36d9ff',color:'#d8f3ff'}}/><Line type="monotone" dataKey="fuel" stroke="#ffcc66" strokeWidth={3}/><Line type="monotone" dataKey="rares" stroke="#bf7dff" strokeWidth={3}/><Line type="monotone" dataKey="electronics" stroke="#36d9ff" strokeWidth={3}/><Line type="monotone" dataKey="components" stroke="#3dff9b" strokeWidth={3}/></LineChart></ResponsiveContainer></Panel><Panel title="Produccion/hora"><ResponsiveContainer width="100%" height={230}><BarChart data={prodData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="name" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:'#07111d',border:'1px solid #36d9ff',color:'#d8f3ff'}}/><Bar dataKey="value" fill="#36d9ff"/></BarChart></ResponsiveContainer></Panel></section></>; }
function MovementTab({ selected, patchSelected, askMovement }) { const [stacksText,setStacksText]=useState(JSON.stringify(selected.stacks||[],null,2)); const [enemyText,setEnemyText]=useState(JSON.stringify(selected.enemy||[],null,2)); useEffect(()=>{setStacksText(JSON.stringify(selected.stacks||[],null,2));setEnemyText(JSON.stringify(selected.enemy||[],null,2));},[selected.id]); function save(){patchSelected({stacks:JSON.parse(stacksText),enemy:JSON.parse(enemyText)});} return <section className="movementGrid"><Panel title="Movement Assistant" right="no ejecuta acciones" icon={<Swords size={16}/>}><p className="hint">Recomienda movimientos, counters y riesgos. No controla el juego.</p><div className="formGrid two"><label>Stacks propios JSON<textarea value={stacksText} onChange={(e)=>setStacksText(e.target.value)}/></label><label>Enemigos observados JSON<textarea value={enemyText} onChange={(e)=>setEnemyText(e.target.value)}/></label></div><div className="row"><button onClick={save}><Save size={16}/> Guardar</button><button onClick={askMovement}><Crosshair size={16}/> Recomendar movimiento</button></div></Panel><Panel title="Matriz de movimiento" icon={<Map size={16}/>}>{(selected.stacks||[]).map((s,i)=><div className="moveCard" key={i}><strong>{s.name}</strong><p><b>Ubicacion:</b> {s.location}</p><p><b>Unidades:</b> {s.units}</p><p><b>Mision:</b> {s.mission}</p><span>{s.threat}</span></div>)}</Panel><Panel title="Contramedidas" icon={<ShieldAlert size={16}/>}>{(selected.enemy||[]).map((e,i)=><div className="moveCard" key={i}><strong>{e.location}</strong><p><b>Observado:</b> {e.observed}</p><p><b>Counter:</b> {e.counter}</p><span>{e.risk}</span></div>)}</Panel></section>; }
function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture }) { return <section className="capturePage"><Panel title="Capture Center" right={captureStatus} icon={<Video size={16}/>}><video ref={videoRef} className="hiddenVideo"/><canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas"/><div className="row"><button onClick={startCapture}>Conectar pantalla</button><button onClick={()=>{setCaptureOpen(true);setTimeout(drawCapture,100)}}><Eye size={16}/> Ampliar</button><button onClick={()=>setCaptureMode(captureMode==='fit'?'fill':'fit')}>Modo {captureMode}</button><button className="danger" onClick={stopCapture}>Parar</button></div><p className="hint">Captura solo observa. No mueve ni hace clicks. v0.9 anadira OCR calibrado.</p></Panel>{captureOpen&&<div className="captureModal"><div className="captureModalTop"><strong>LIVE GAME FEED</strong><div className="row"><button onClick={()=>setCaptureMode(captureMode==='fit'?'fill':'fit')}>Modo {captureMode}</button><button className="danger" onClick={()=>setCaptureOpen(false)}>Cerrar</button></div></div><canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig"/></div>}</section>; }
function DataTab({ selected, patchSelected, games, exportJson, importJson }) { const [fronts,setFronts]=useState(JSON.stringify(selected.fronts||[],null,2)); const [research,setResearch]=useState((selected.research||[]).join(', ')); const [notes,setNotes]=useState(selected.notes||''); const [io,setIo]=useState(''); useEffect(()=>{setFronts(JSON.stringify(selected.fronts||[],null,2));setResearch((selected.research||[]).join(', '));setNotes(selected.notes||'');},[selected.id]); function saveData(){patchSelected({fronts:JSON.parse(fronts),research:research.split(',').map(x=>x.trim()).filter(Boolean),notes});} return <section className="dataGrid"><Panel title="Datos de partida"><div className="formGrid three"><label>Frentes JSON<textarea value={fronts} onChange={(e)=>setFronts(e.target.value)}/></label><label>Research<textarea value={research} onChange={(e)=>setResearch(e.target.value)}/></label><label>Notas<textarea value={notes} onChange={(e)=>setNotes(e.target.value)}/></label></div><button onClick={saveData}>Guardar datos</button></Panel><Panel title="Import / Export JSON"><textarea value={io} onChange={(e)=>setIo(e.target.value)}/><div className="row"><button onClick={()=>{setIo(JSON.stringify(games,null,2));exportJson();}}>Exportar todo</button><button onClick={()=>importJson(io)}>Importar</button></div></Panel></section>; }

createRoot(document.getElementById("root")).render(<App />);
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\src\main.jsx"

@'
:root{--bg:#02050b;--panel:rgba(7,18,30,.92);--cyan:#36d9ff;--green:#3dff9b;--red:#ff4d5f;--amber:#ffcc66;--text:#d8f3ff;--muted:#86a8ba;--border:rgba(54,217,255,.25)}*{box-sizing:border-box}html,body,#root{min-height:100%;margin:0}body{background:radial-gradient(circle at 12% 10%,rgba(54,217,255,.15),transparent 28%),radial-gradient(circle at 80% 2%,rgba(61,255,155,.11),transparent 24%),linear-gradient(135deg,#010309,#07111d 50%,#010208);color:var(--text);font-family:Inter,Segoe UI,Arial,sans-serif}body:before{content:"";position:fixed;inset:0;pointer-events:none;background-image:linear-gradient(rgba(54,217,255,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(54,217,255,.045) 1px,transparent 1px);background-size:42px 42px;mask-image:radial-gradient(circle at center,black 0%,transparent 82%)}button,input,textarea,select{font:inherit}button{display:inline-flex;align-items:center;justify-content:center;gap:8px;border:1px solid var(--cyan);background:rgba(54,217,255,.11);color:var(--cyan);padding:10px 13px;border-radius:12px;font-weight:900;text-transform:uppercase;letter-spacing:.8px;cursor:pointer}button:hover{background:rgba(54,217,255,.22);box-shadow:0 0 18px rgba(54,217,255,.22)}button.danger{border-color:var(--red);color:var(--red);background:rgba(255,77,95,.08)}button.good{border-color:var(--green);color:var(--green)}button.warn{border-color:var(--amber);color:var(--amber)}input,textarea,select{width:100%;background:rgba(0,0,0,.32);border:1px solid rgba(54,217,255,.24);border-radius:12px;color:var(--text);padding:10px 12px;outline:none}textarea{min-height:180px;font-family:Consolas,monospace;font-size:12px}label{display:block;color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:1px}label input,label textarea,label select{margin-top:6px}.app{display:grid;grid-template-columns:300px minmax(760px,1fr)430px;grid-template-rows:auto 1fr;gap:16px;padding:18px;position:relative;z-index:1}.topbar{grid-column:1/-1;display:flex;justify-content:space-between;gap:18px;align-items:center}.eyebrow{color:var(--muted);letter-spacing:3px;text-transform:uppercase;font-size:12px}h1{margin:6px 0 0;font-size:34px;letter-spacing:2px;text-transform:uppercase;text-shadow:0 0 22px rgba(54,217,255,.55)}.topActions,.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.pill{border:1px solid var(--border);border-radius:999px;padding:9px 13px;font-weight:900;background:rgba(54,217,255,.08)}.pill.good{color:var(--green)}.pill.danger{color:var(--red)}.sidebar,.main,.rightbar{display:flex;flex-direction:column;gap:14px}.panel,.metricCard{border:1px solid var(--border);background:linear-gradient(180deg,var(--panel),rgba(3,9,16,.93));border-radius:18px;padding:15px;box-shadow:0 18px 60px rgba(0,0,0,.36),inset 0 0 24px rgba(54,217,255,.035)}.panelTitle{display:flex;justify-content:space-between;gap:10px;margin-bottom:12px;color:var(--muted)}.panelTitle h2{margin:0;display:flex;align-items:center;gap:8px;font-size:13px;text-transform:uppercase;letter-spacing:1.5px}.gameList{display:flex;flex-direction:column;gap:10px}.gameBtn{text-align:left;display:block;width:100%;background:rgba(255,255,255,.035);border-color:rgba(255,255,255,.08);color:var(--text)}.gameBtn.active{border-color:var(--cyan);background:rgba(54,217,255,.14);box-shadow:0 0 24px rgba(54,217,255,.16)}.gameBtn strong{display:block}.gameBtn span{display:block;color:var(--muted);font-size:12px;margin-top:5px}.tabNav{display:grid;grid-template-columns:1fr 1fr;gap:8px}.tabNav button.active{background:rgba(54,217,255,.24)}.metrics{display:grid;grid-template-columns:repeat(5,1fr);gap:10px}.metricCard h3{margin:0 0 8px;color:var(--muted);letter-spacing:1.5px;text-transform:uppercase;font-size:12px}.metricValue{font-size:26px;font-weight:950;line-height:1}.hint{color:var(--muted);font-size:12px;margin:8px 0 0}.formGrid{display:grid;gap:10px;margin-bottom:10px}.formGrid.two{grid-template-columns:1fr 1fr}.formGrid.three{grid-template-columns:repeat(3,1fr)}.formGrid.four{grid-template-columns:repeat(4,1fr)}.resourceGrid{display:grid;grid-template-columns:repeat(2,minmax(300px,1fr));gap:10px}.resourceCard{border:1px solid rgba(255,255,255,.08);border-left:3px solid var(--cyan);background:rgba(255,255,255,.035);border-radius:16px;padding:13px}.resourceCard.critical{border-left-color:var(--red)}.resourceCard.low{border-left-color:var(--amber)}.resourceCard.stable{border-left-color:var(--green)}.resourceTop{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}.resourceTop strong{display:flex;align-items:center;gap:9px;text-transform:uppercase}.resourceTop strong span{font-size:22px}.resourceTop em{font-style:normal;color:var(--red)}.stable .resourceTop em{color:var(--green)}.low .resourceTop em{color:var(--amber)}.bar{height:6px;background:rgba(255,255,255,.08);border-radius:999px;overflow:hidden}.bar i{display:block;height:100%;background:linear-gradient(90deg,var(--cyan),var(--green))}.chartGrid{display:grid;grid-template-columns:1fr 1fr;gap:14px}.radarBox{height:250px;border-radius:50%;position:relative;margin:0 auto 12px;max-width:250px;border:1px solid rgba(54,217,255,.35);background:radial-gradient(circle,transparent 0 22%,rgba(54,217,255,.08) 23% 24%,transparent 25% 46%,rgba(54,217,255,.08) 47% 48%,transparent 49%),conic-gradient(from 35deg,rgba(61,255,155,.3),transparent 25%,transparent)}.radarDot{position:absolute;width:8px;height:8px;border-radius:50%;left:60%;top:20%;background:var(--red);box-shadow:0 0 15px var(--red)}.radarDot.amber{left:25%;top:70%;background:var(--amber);box-shadow:0 0 15px var(--amber)}.radarDot.cyan{left:70%;top:62%;background:var(--cyan);box-shadow:0 0 15px var(--cyan)}.frontItem,.feedItem,.moveCard{border-left:3px solid var(--cyan);background:rgba(54,217,255,.055);border-radius:12px;padding:10px;margin-bottom:8px}.frontItem p,.feedItem p,.moveCard p{margin:5px 0;color:var(--muted);font-size:12px}.frontItem span,.moveCard span{font-size:11px;border:1px solid var(--border);border-radius:999px;padding:4px 8px;color:var(--cyan)}.advisor{min-height:310px;color:var(--green)}.movementGrid,.dataGrid,.capturePage{display:flex;flex-direction:column;gap:14px}.captureCanvas{width:100%;height:520px;background:#000;border:1px solid rgba(54,217,255,.25);border-radius:18px;display:block}.hiddenVideo{display:none}.captureModal{position:fixed;z-index:9999;inset:0;background:rgba(0,0,0,.92);display:grid;grid-template-rows:auto 1fr;padding:20px;gap:12px}.captureModalTop{display:flex;justify-content:space-between;align-items:center;border:1px solid var(--border);background:rgba(7,18,30,.92);border-radius:16px;padding:12px}.captureBig{width:100%;height:100%;background:#000;border:1px solid var(--border);border-radius:18px}@media(max-width:1400px){.app{grid-template-columns:280px 1fr}.rightbar{grid-column:1/-1}.metrics{grid-template-columns:repeat(3,1fr)}}@media(max-width:900px){.app,.metrics,.resourceGrid,.chartGrid,.formGrid.two,.formGrid.three,.formGrid.four{grid-template-columns:1fr}.topbar{align-items:flex-start;flex-direction:column}}
'@ | Set-Content -Encoding UTF8 ".\02-apps\warroom-web\src\styles.css"

Write-Host "v0.8 React Command Center aplicado correctamente." -ForegroundColor Green
Write-Host "Siguiente: git add . ; git commit ; git push ; Build warroom-web ; rollout restart." -ForegroundColor Yellow
