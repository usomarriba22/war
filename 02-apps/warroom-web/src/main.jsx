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