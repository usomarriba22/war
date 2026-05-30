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
  const [captureMarks, setCaptureMarks] = useState([]);
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
    <main className="main">{activeTab === "command" && <CommandTab selected={selected} patchSelected={patchSelected} updateResource={updateResource} chartData={chartData} prodData={prodData}/>} {activeTab === "movement" && <MovementTab selected={selected} patchSelected={patchSelected} askMovement={()=>askAdvisor("movement")}/>} {activeTab === "capture" && <CaptureTab videoRef={videoRef} previewCanvasRef={previewCanvasRef} bigCanvasRef={bigCanvasRef} captureOpen={captureOpen} setCaptureOpen={setCaptureOpen} captureStatus={captureStatus} captureMode={captureMode} setCaptureMode={setCaptureMode} startCapture={startCapture} stopCapture={stopCapture} drawCapture={drawCapture}
            captureMarks={captureMarks}
            setCaptureMarks={setCaptureMarks}
          />} {activeTab === "data" && <DataTab selected={selected} patchSelected={patchSelected} games={games} exportJson={exportJson} importJson={importJson}/>}</main>
    <aside className="rightbar"><Panel title="Threat Radar" right={`${(selected.fronts||[]).filter(f=>["high","critical"].includes(f.risk)).length} high risk`} icon={<Radar size={16}/>}><div className="radarBox"><span className="radarDot red"></span><span className="radarDot amber"></span><span className="radarDot cyan"></span></div>{(selected.fronts||[]).map((f,i)=><FrontItem key={i} f={f}/>)}</Panel><Panel title="Assistant" right="advisor" icon={<Brain size={16}/>}><textarea className="advisor" value={advisor} onChange={(e)=>setAdvisor(e.target.value)} /><div className="row"><button onClick={()=>askAdvisor("general")}><Bot size={16}/> Ask</button><button onClick={()=>askAdvisor("movement")}><Crosshair size={16}/> Movement</button><button onClick={()=>navigator.clipboard.writeText(advisor)}>Copiar</button></div></Panel><Panel title="Activity Feed" icon={<Activity size={16}/>}><div className="feed">{(selected.feed||[]).slice().reverse().slice(0,12).map((item,i)=><div className={`feedItem ${item.level||""}`} key={i}><strong>{new Date(item.time).toLocaleTimeString()}</strong><p>{item.text}</p></div>)}</div></Panel></aside>
  </div>;
}

function Panel({ title, right, icon, children }) { return <section className="panel"><div className="panelTitle"><h2>{icon}{title}</h2>{right && <span>{right}</span>}</div>{children}</section>; }
function Metric({ label, value, sub }) { return <div className="metricCard"><h3>{label}</h3><div className="metricValue">{value}</div><div className="hint">{sub}</div></div>; }
function ResourceCard({ meta, r, onChange }) { return <div className={`resourceCard ${r.status}`}><div className="resourceTop"><strong><img className="resImage" src={meta.img} alt={meta.label} />{meta.label}</strong><em>{r.status}</em></div><div className="formGrid three"><label>Stock<input type="number" value={Math.round(Number(r.value||0))} onChange={(e)=>onChange("value", e.target.value)}/></label><label>Hora<input type="number" value={r.hour} onChange={(e)=>onChange("hour", e.target.value)}/></label><label>Status<select value={r.status} onChange={(e)=>onChange("status", e.target.value)}><option>stable</option><option>low</option><option>critical</option></select></label></div><div className="bar"><i style={{width:`${Math.max(4,Math.min(100,Number(r.value||0)/meta.target*100))}%`}} /></div><p className="hint">target tactico: {meta.target}</p></div>; }
function FrontItem({ f }) { return <div className="frontItem"><strong>{f.name}</strong><p>{f.state} - {f.action}</p><span>{f.risk}</span></div>; }
function CommandTab({ selected, patchSelected, updateResource, chartData, prodData }) { return <><section className="metrics"><Metric label="Partida" value={selected.name} sub={selected.country}/><Metric label="Dia" value={selected.day} sub="ciclo operativo"/><Metric label="VP" value={selected.victory_points} sub="victory points"/><Metric label="Readiness" value={`${readinessScore(selected)}%`} sub="economia + frentes"/><Metric label="ETA Critico" value={getCriticalEta(selected)} sub="primer recurso bajo"/></section><Panel title="Ficha de partida"><div className="formGrid four"><label>Nombre<input value={selected.name} onChange={(e)=>patchSelected({name:e.target.value})}/></label><label>Pais<input value={selected.country} onChange={(e)=>patchSelected({country:e.target.value})}/></label><label>Dia<input type="number" value={selected.day} onChange={(e)=>patchSelected({day:Number(e.target.value)})}/></label><label>VP<input value={selected.victory_points} onChange={(e)=>patchSelected({victory_points:e.target.value})}/></label></div></Panel><Panel title="Economy Radar Live"><div className="resourceGrid">{Object.entries(RESOURCE_META).map(([key,meta])=><ResourceCard key={key} meta={meta} r={selected.resources[key]} onChange={(prop,value)=>updateResource(key,prop,value)}/>)}</div></Panel><section className="chartGrid"><Panel title="Historico de stock"><ResponsiveContainer width="100%" height={230}><LineChart data={chartData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="idx" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:'#07111d',border:'1px solid #36d9ff',color:'#d8f3ff'}}/><Line type="monotone" dataKey="fuel" stroke="#ffcc66" strokeWidth={3}/><Line type="monotone" dataKey="rares" stroke="#bf7dff" strokeWidth={3}/><Line type="monotone" dataKey="electronics" stroke="#36d9ff" strokeWidth={3}/><Line type="monotone" dataKey="components" stroke="#3dff9b" strokeWidth={3}/></LineChart></ResponsiveContainer></Panel><Panel title="Produccion/hora"><ResponsiveContainer width="100%" height={230}><BarChart data={prodData}><CartesianGrid stroke="rgba(54,217,255,.12)"/><XAxis dataKey="name" stroke="#7f9eb2"/><YAxis stroke="#7f9eb2"/><Tooltip contentStyle={{background:'#07111d',border:'1px solid #36d9ff',color:'#d8f3ff'}}/><Bar dataKey="value" fill="#36d9ff"/></BarChart></ResponsiveContainer></Panel></section></>; }
function MovementTab({ selected, patchSelected, askMovement }) { const [stacksText,setStacksText]=useState(JSON.stringify(selected.stacks||[],null,2)); const [enemyText,setEnemyText]=useState(JSON.stringify(selected.enemy||[],null,2)); useEffect(()=>{setStacksText(JSON.stringify(selected.stacks||[],null,2));setEnemyText(JSON.stringify(selected.enemy||[],null,2));},[selected.id]); function save(){patchSelected({stacks:JSON.parse(stacksText),enemy:JSON.parse(enemyText)});} return <section className="movementGrid"><Panel title="Movement Assistant" right="no ejecuta acciones" icon={<Swords size={16}/>}><p className="hint">Recomienda movimientos, counters y riesgos. No controla el juego.</p><div className="formGrid two"><label>Stacks propios JSON<textarea value={stacksText} onChange={(e)=>setStacksText(e.target.value)}/></label><label>Enemigos observados JSON<textarea value={enemyText} onChange={(e)=>setEnemyText(e.target.value)}/></label></div><div className="row"><button onClick={save}><Save size={16}/> Guardar</button><button onClick={askMovement}><Crosshair size={16}/> Recomendar movimiento</button></div></Panel><Panel title="Matriz de movimiento" icon={<Map size={16}/>}>{(selected.stacks||[]).map((s,i)=><div className="moveCard" key={i}><strong>{s.name}</strong><p><b>Ubicacion:</b> {s.location}</p><p><b>Unidades:</b> {s.units}</p><p><b>Mision:</b> {s.mission}</p><span>{s.threat}</span></div>)}</Panel><Panel title="Contramedidas" icon={<ShieldAlert size={16}/>}>{(selected.enemy||[]).map((e,i)=><div className="moveCard" key={i}><strong>{e.location}</strong><p><b>Observado:</b> {e.observed}</p><p><b>Counter:</b> {e.counter}</p><span>{e.risk}</span></div>)}</Panel></section>; }
function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks }) {
  function addCaptureMark(e) {
    if (e.button !== 0) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * 100;
    const y = ((e.clientY - rect.top) / rect.height) * 100;
    const label = prompt("Marcador tactico: unidad, enemigo, ciudad u objetivo", "objetivo");
    if (!label) return;
    setCaptureMarks([...(captureMarks || []), { x, y, label, time: new Date().toISOString() }]);
  }

  function clearCaptureMarks() {
    setCaptureMarks([]);
  } return <section className="capturePage"><Panel title="Capture Center" right={captureStatus} icon={<Video size={16}/>}><video ref={videoRef} className="hiddenVideo"/><canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas"/><div className="row"><button onClick={startCapture}>Conectar pantalla</button><button onClick={()=>{setCaptureOpen(true);setTimeout(drawCapture,100)}}><Eye size={16}/> Ampliar</button><button onClick={()=>setCaptureMode(captureMode==='fit'?'fill':'fit')}>Modo {captureMode}</button><button className="danger" onClick={stopCapture}>Parar</button></div><p className="hint">Captura solo observa. No mueve ni hace clicks. v0.9 anadira OCR calibrado.</p></Panel>{captureOpen&&<div className="captureModal"><div className="captureModalTop"><strong>LIVE GAME FEED</strong><div className="row"><button onClick={()=>setCaptureMode(captureMode==='fit'?'fill':'fit')}>Modo {captureMode}</button><button className="danger" onClick={()=>setCaptureOpen(false)}>Cerrar</button></div></div><canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig"/></div>}</section>; }
function DataTab({ selected, patchSelected, games, exportJson, importJson }) { const [fronts,setFronts]=useState(JSON.stringify(selected.fronts||[],null,2)); const [research,setResearch]=useState((selected.research||[]).join(', ')); const [notes,setNotes]=useState(selected.notes||''); const [io,setIo]=useState(''); useEffect(()=>{setFronts(JSON.stringify(selected.fronts||[],null,2));setResearch((selected.research||[]).join(', '));setNotes(selected.notes||'');},[selected.id]); function saveData(){patchSelected({fronts:JSON.parse(fronts),research:research.split(',').map(x=>x.trim()).filter(Boolean),notes});} return <section className="dataGrid"><Panel title="Datos de partida"><div className="formGrid three"><label>Frentes JSON<textarea value={fronts} onChange={(e)=>setFronts(e.target.value)}/></label><label>Research<textarea value={research} onChange={(e)=>setResearch(e.target.value)}/></label><label>Notas<textarea value={notes} onChange={(e)=>setNotes(e.target.value)}/></label></div><button onClick={saveData}>Guardar datos</button></Panel><Panel title="Import / Export JSON"><textarea value={io} onChange={(e)=>setIo(e.target.value)}/><div className="row"><button onClick={()=>{setIo(JSON.stringify(games,null,2));exportJson();}}>Exportar todo</button><button onClick={()=>importJson(io)}>Importar</button></div></Panel></section>; }

createRoot(document.getElementById("root")).render(<App />);
