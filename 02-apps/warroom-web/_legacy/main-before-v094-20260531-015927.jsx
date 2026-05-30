import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Activity, Bot, Crosshair, Eye, Gamepad2, Map, Radar, Save, ShieldAlert, Swords, Target, Video, Zap } from "lucide-react";
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
function snapshot(game) {
  return { time: nowIso(), day: game.day, victory_points: game.victory_points, resources: JSON.parse(JSON.stringify(game.resources)), readiness: readinessScore(game) };
}
function criticalEta(game) {
  const entry = Object.entries(game.resources || {}).find(([, r]) => r.status === "critical" || r.status === "low");
  return entry ? `${RESOURCE_META[entry[0]]?.label || entry[0]} bajo` : "OK";
}
function parseOcrNumbers(text) {
  const raw = (text || "").replace(/[Oo]/g, "0");
  const nums = raw.match(/\d[\d.,]*/g) || [];
  return nums.map(n => Number(n.replace(/[.,]/g, ""))).filter(n => Number.isFinite(n) && n >= 10);
}

function App() {
  const [games, setGames] = useState(readGames);
  const [selectedId, setSelectedId] = useState(() => readGames()[0]?.id);
  const [tab, setTab] = useState("command");
  const [apiOk, setApiOk] = useState(false);
  const [live, setLive] = useState(true);
  const [clock, setClock] = useState(new Date());
  const [advisor, setAdvisor] = useState("Pulsa Ask o Movement para generar recomendaciones.");
  const [movementPlan, setMovementPlan] = useState("Movement Assistant listo. Carga stacks/enemigos y pulsa Recomendar movimiento.");
  const [captureStatus, setCaptureStatus] = useState("offline");
  const [captureOpen, setCaptureOpen] = useState(false);
  const [captureMode, setCaptureMode] = useState("fit");
  const [marks, setMarks] = useState([]);
  const [markLabel, setMarkLabel] = useState("objetivo");
  const [ocrText, setOcrText] = useState("");
  const [ocrNumbers, setOcrNumbers] = useState([]);
  const [segmentedOcr, setSegmentedOcr] = useState([]);
  const [ocrEditable, setOcrEditable] = useState([]);
  const [captureSize, setCaptureSize] = useState("compact");
  const [ocrBusy, setOcrBusy] = useState(false);
  const [ocrCrop, setOcrCrop] = useState({ x: 34, y: 0, w: 60, h: 12, threshold: 95, scale: 4 });

  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const bigCanvasRef = useRef(null);
  const cropCanvasRef = useRef(null);
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
  async function askGeneral() {
    try {
      const res = await fetch(`${API_BASE}/api/advisor/analyze`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ game_state: selected, question: "Analiza la partida y da acciones proximas 6-12 horas." }) });
      const data = await res.json();
      setAdvisor(data.answer || JSON.stringify(data, null, 2));
      replaceSelected(addFeed(selected, "Advisor generado", "info"));
    } catch (e) { setAdvisor(`Error: ${e.message}`); }
  }
  async function askMovement() {
    try {
      const res = await fetch(`${API_BASE}/api/movement/analyze`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ game_state: selected, marks }) });
      const data = await res.json();
      const text = data.plan || data.answer || JSON.stringify(data, null, 2);
      setMovementPlan(text);
      setAdvisor(text);
      replaceSelected(addFeed(selected, "Movement plan generado", "info"));
    } catch (e) { setMovementPlan(`Error: ${e.message}`); }
  }
  function applyOcrToResources() {
    if (ocrNumbers.length < 7) return alert("OCR no detecto 7 numeros. Ajusta captura/zoom y prueba otra vez.");
    const resources = { ...selected.resources };
    RESOURCE_KEYS.forEach((key, i) => {
      const value = ocrNumbers[i];
      resources[key] = { ...resources[key], value, status: deriveStatus(key, value) };
    });
    replaceSelected(addFeed({ ...selected, resources, live_base_at: nowIso() }, "OCR aplicado a recursos", "info"));
  }

  async function runSegmentedOcr() {
    const src = canvasRef.current;
    if (!src) return;

    setOcrBusy(true);
    try {
      const Tesseract = await import("tesseract.js");

      const sx = Math.round(src.width * (ocrCrop.x / 100));
      const sy = Math.round(src.height * (ocrCrop.y / 100));
      const sw = Math.round(src.width * (ocrCrop.w / 100));
      const sh = Math.round(src.height * (ocrCrop.h / 100));

      const results = [];

      for (let i = 0; i < RESOURCE_KEYS.length; i++) {
        const key = RESOURCE_KEYS[i];
        const meta = RESOURCE_META[key];

        const segW = Math.round(sw / RESOURCE_KEYS.length);
        const segX = sx + (i * segW);

        // Dentro de cada recurso, ignoramos el icono de la izquierda y el margen.
        // El texto suele estar en el 35%-98% de cada caja.
        const textX = segX + Math.round(segW * 0.30);
        const textW = Math.max(14, Math.round(segW * 0.68));

        const scale = Number(ocrCrop.scale || 6);
        const segCanvas = document.createElement("canvas");
        segCanvas.width = Math.max(320, textW * scale);
        segCanvas.height = Math.max(150, sh * scale);

        const ctx = segCanvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;
        ctx.fillStyle = "#000";
        ctx.fillRect(0, 0, segCanvas.width, segCanvas.height);
        ctx.drawImage(src, textX, sy, textW, sh, 0, 0, segCanvas.width, segCanvas.height);

        // Probar dos preprocesados: binario y original invertido simple.
        const img = ctx.getImageData(0, 0, segCanvas.width, segCanvas.height);
        const threshold = Number(ocrCrop.threshold || 110);

        for (let p = 0; p < img.data.length; p += 4) {
          const r = img.data[p];
          const g = img.data[p + 1];
          const b = img.data[p + 2];
          const brightness = (r + g + b) / 3;
          const greenBoost = g > r + 8 && g > b + 8 ? 50 : 0;
          const whiteBoost = r > 150 && g > 150 && b > 150 ? 45 : 0;
          const v = brightness + greenBoost + whiteBoost > threshold ? 255 : 0;
          img.data[p] = v;
          img.data[p + 1] = v;
          img.data[p + 2] = v;
        }
        ctx.putImageData(img, 0, 0);

        const ocr = await Tesseract.recognize(segCanvas, "eng", {
          tessedit_char_whitelist: "0123456789,+/h ",
          preserve_interword_spaces: "1"
        });

        const text = ocr?.data?.text || "";
        const nums = parseOcrNumbers(text);

        // Heuristica:
        // stock suele ser el primer numero grande; hora suele ser el ultimo numero.
        // Si OCR no pilla hora, queda editable.
        const stock = nums.length ? nums[0] : null;
        const hour = nums.length >= 2 ? nums[nums.length - 1] : null;

        results.push({
          key,
          label: meta.label,
          text,
          nums,
          stock,
          hour
        });
      }

      setSegmentedOcr(results);
      setOcrEditable(results.map(r => ({
        key: r.key,
        label: r.label,
        stock: r.stock ?? "",
        hour: r.hour ?? "",
        raw: (r.text || "").replace(/\s+/g, " ").trim()
      })));

      setOcrText(results.map(r => `${r.label}: ${r.text.replace(/\s+/g, " ").trim()} => ${r.nums.join(" / ")}`).join("\n"));
      setOcrNumbers(results.map(r => r.stock).filter(n => n !== null));
    } catch (e) {
      setOcrText(`Segmented OCR error: ${e.message}`);
    }
    setOcrBusy(false);
  }

  function updateOcrEditable(key, field, value) {
    setOcrEditable((old) => old.map((x) => x.key === key ? { ...x, [field]: value } : x));
  }

  function applySegmentedOcrToResources() {
    const source = (ocrEditable && ocrEditable.length) ? ocrEditable : segmentedOcr;

    if (!source || source.length < 7) {
      return alert("Primero ejecuta OCR por cajas o rellena la tabla editable.");
    }

    const resources = { ...selected.resources };

    source.forEach((item) => {
      if (!item || !item.key) return;
      const current = resources[item.key] || {};
      const next = { ...current };

      const stock = Number(item.stock);
      const hour = Number(item.hour);

      if (Number.isFinite(stock) && stock >= 0) {
        next.value = stock;
        next.status = deriveStatus(item.key, next.value);
      }

      if (Number.isFinite(hour)) {
        next.hour = hour;
      }

      resources[item.key] = next;
    });

    replaceSelected(addFeed({ ...selected, resources, live_base_at: nowIso() }, "OCR validado aplicado a recursos", "info"));
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
  async function runOcrTopBar() {
    const src = canvasRef.current;
    const crop = cropCanvasRef.current;
    if (!src || !crop) return;

    setOcrBusy(true);
    try {
      const ctx = crop.getContext("2d");

      const sx = Math.round(src.width * (ocrCrop.x / 100));
      const sy = Math.round(src.height * (ocrCrop.y / 100));
      const sw = Math.round(src.width * (ocrCrop.w / 100));
      const sh = Math.round(src.height * (ocrCrop.h / 100));

      crop.width = Math.max(800, sw * Number(ocrCrop.scale || 4));
      crop.height = Math.max(120, sh * Number(ocrCrop.scale || 4));

      ctx.imageSmoothingEnabled = false;
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, crop.width, crop.height);
      ctx.drawImage(src, sx, sy, sw, sh, 0, 0, crop.width, crop.height);

      const img = ctx.getImageData(0, 0, crop.width, crop.height);
      const threshold = Number(ocrCrop.threshold || 95);

      for (let i = 0; i < img.data.length; i += 4) {
        const r = img.data[i];
        const g = img.data[i + 1];
        const b = img.data[i + 2];

        // Dar prioridad a texto blanco/verde claro sobre fondo oscuro.
        const brightness = (r + g + b) / 3;
        const greenBoost = g > r + 15 && g > b + 15 ? 35 : 0;
        const v = brightness + greenBoost > threshold ? 255 : 0;

        img.data[i] = v;
        img.data[i + 1] = v;
        img.data[i + 2] = v;
      }

      ctx.putImageData(img, 0, 0);

      const Tesseract = await import("tesseract.js");
      const result = await Tesseract.recognize(crop, "eng", {
        tessedit_char_whitelist: "0123456789,+/h ",
        preserve_interword_spaces: "1"
      });

      const text = result?.data?.text || "";
      const numbers = parseOcrNumbers(text);

      setOcrText(text);
      setOcrNumbers(numbers);
    } catch (e) {
      setOcrText(`OCR error: ${e.message}`);
    }
    setOcrBusy(false);
  }

  const chartData = (selected.snapshots || []).slice(-12).map((s, i) => ({ idx: i, fuel: s.resources?.fuel?.value || 0, rares: s.resources?.rares?.value || 0, electronics: s.resources?.electronics?.value || 0, components: s.resources?.components?.value || 0 }));
  const prodData = RESOURCE_KEYS.map(k => ({ name: RESOURCE_META[k].short, value: Number(selected.resources?.[k]?.hour || 0) }));

  return (
    <div className="app">
      <header className="topbar">
        <div><div className="eyebrow">CON War Room v0.9</div><h1>Live Tactical Command Center</h1></div>
        <div className="topActions"><span className={apiOk ? "pill good" : "pill danger"}>API {apiOk ? "ONLINE" : "OFFLINE"}</span><span className="pill">{clock.toLocaleTimeString()}</span><button className={live ? "good" : "warn"} onClick={() => setLive(!live)}><Zap size={16}/> {live ? "Live ON" : "Live OFF"}</button><button onClick={saveSnapshot}><Save size={16}/> Snapshot</button></div>
      </header>

      <aside className="sidebar">
        <Panel title="Partidas" right={games.length}>{games.map(g => <button key={g.id} className={`gameBtn ${g.id===selected.id ? "active" : ""}`} onClick={() => setSelectedId(g.id)}><strong>{g.name}</strong><span>{g.country} - Dia {g.day} - {readinessScore(g)}% ready</span></button>)}<div className="row"><button onClick={createGame}>Nueva</button><button className="danger" onClick={deleteGame}>Borrar</button></div></Panel>
        <Panel title="Tabs"><nav className="tabNav">{[["command","Command"],["movement","Movement"],["capture","Capture"],["data","Data"]].map(([id,l]) => <button key={id} className={tab===id ? "active":""} onClick={() => setTab(id)}>{l}</button>)}</nav></Panel>
        <Panel title="Live Engine"><p className="hint">Recursos por live tick + OCR top bar. Captura observa, no controla el juego.</p></Panel>
      </aside>

      <main className="main">
        {tab === "command" && <CommandTab selected={selected} patchSelected={patchSelected} updateResource={updateResource} chartData={chartData} prodData={prodData} />}
        {tab === "movement" && <MovementTab selected={selected} patchSelected={patchSelected} askMovement={askMovement} movementPlan={movementPlan} />}
        {tab === "capture" && <CaptureTab videoRef={videoRef} canvasRef={canvasRef} bigCanvasRef={bigCanvasRef} cropCanvasRef={cropCanvasRef} captureOpen={captureOpen} setCaptureOpen={setCaptureOpen} captureStatus={captureStatus} captureMode={captureMode} setCaptureMode={setCaptureMode} startCapture={startCapture} stopCapture={stopCapture} addMark={addMark} marks={marks} setMarks={setMarks} markLabel={markLabel} setMarkLabel={setMarkLabel} runOcrTopBar={runOcrTopBar} ocrBusy={ocrBusy} ocrText={ocrText} ocrNumbers={ocrNumbers} applyOcrToResources={applyOcrToResources} ocrCrop={ocrCrop} setOcrCrop={setOcrCrop} segmentedOcr={segmentedOcr} ocrEditable={ocrEditable} updateOcrEditable={updateOcrEditable} runSegmentedOcr={runSegmentedOcr} applySegmentedOcrToResources={applySegmentedOcrToResources} captureSize={captureSize} setCaptureSize={setCaptureSize} />}
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
function MovementTab({ selected, patchSelected, askMovement, movementPlan }) {
  const [stacks, setStacks] = useState(JSON.stringify(selected.stacks||[], null, 2));
  const [enemy, setEnemy] = useState(JSON.stringify(selected.enemy||[], null, 2));
  useEffect(()=>{setStacks(JSON.stringify(selected.stacks||[], null, 2)); setEnemy(JSON.stringify(selected.enemy||[], null, 2));}, [selected.id]);
  function save(){ patchSelected({ stacks: JSON.parse(stacks), enemy: JSON.parse(enemy) }); }
  return <section className="movementGrid"><Panel title="Movement Assistant"><p className="hint">No ejecuta acciones. Recomienda movimientos, contramedidas y que NO mover.</p><div className="formGrid two"><label>Stacks propios JSON<textarea value={stacks} onChange={e=>setStacks(e.target.value)}/></label><label>Enemigos observados JSON<textarea value={enemy} onChange={e=>setEnemy(e.target.value)}/></label></div><div className="row"><button onClick={save}><Save size={16}/> Guardar</button><button onClick={askMovement}><Target size={16}/> Recomendar movimiento</button></div></Panel><Panel title="Plan de movimiento"><textarea className="advisor" value={movementPlan} readOnly/></Panel><section className="moveCols"><Panel title="Stacks propios">{(selected.stacks||[]).map((s,i)=><MoveCard key={i} item={s}/>)}</Panel><Panel title="Contramedidas">{(selected.enemy||[]).map((e,i)=><MoveCard key={i} item={e}/>)}</Panel></section></section>;
}
function MoveCard({ item }) { return <div className="moveCard"><strong>{item.name || item.location}</strong>{Object.entries(item).map(([k,v])=><p key={k}><b>{k}:</b> {String(v)}</p>)}</div>; }
function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop, segmentedOcr, ocrEditable, updateOcrEditable, runSegmentedOcr, applySegmentedOcrToResources, captureSize, setCaptureSize }) {
  return <section className="capturePage"><Panel title="Capture Center + OCR" right={captureStatus}><video ref={videoRef} className="hiddenVideo"/><div className={`captureStage ${captureSize}`} onPointerDown={addMark}><canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/><div className="ocrBoxOverlay" style={{ left: `${ocrCrop.x}%`, top: `${ocrCrop.y}%`, width: `${ocrCrop.w}%`, height: `${ocrCrop.h}%` }}><span>OCR TOP BAR</span></div>{marks.map((m,i)=><div className="captureMark" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}</div><div className="row"><input className="markInput" value={markLabel} onChange={e=>setMarkLabel(e.target.value)} placeholder="texto del marcador"/><button onClick={startCapture}><Video size={16}/> Conectar pantalla</button><button onClick={()=>setCaptureOpen(true)}><Eye size={16}/> Ampliar</button><button onClick={()=>setCaptureSize(captureSize==="compact"?"large":"compact")}>Tamano {captureSize}</button><button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button><button onClick={()=>setMarks([])}>Limpiar marcas</button><button className="danger" onClick={stopCapture}>Parar</button></div><p className="hint">Click sobre la captura crea marcador tactico. Captura observa, no controla el juego.</p></Panel><Panel title="OCR Top Bar Calibrator">
  <div className="ocrControls">
    <label>X %<input type="range" min="0" max="100" value={ocrCrop.x} onChange={e=>setOcrCrop({...ocrCrop, x:Number(e.target.value)})}/><b>{ocrCrop.x}</b></label>
    <label>Y %<input type="range" min="0" max="50" value={ocrCrop.y} onChange={e=>setOcrCrop({...ocrCrop, y:Number(e.target.value)})}/><b>{ocrCrop.y}</b></label>
    <label>W %<input type="range" min="10" max="100" value={ocrCrop.w} onChange={e=>setOcrCrop({...ocrCrop, w:Number(e.target.value)})}/><b>{ocrCrop.w}</b></label>
    <label>H %<input type="range" min="4" max="35" value={ocrCrop.h} onChange={e=>setOcrCrop({...ocrCrop, h:Number(e.target.value)})}/><b>{ocrCrop.h}</b></label>
    <label>Threshold<input type="range" min="40" max="220" value={ocrCrop.threshold} onChange={e=>setOcrCrop({...ocrCrop, threshold:Number(e.target.value)})}/><b>{ocrCrop.threshold}</b></label>
    <label>Scale<input type="range" min="2" max="8" value={ocrCrop.scale} onChange={e=>setOcrCrop({...ocrCrop, scale:Number(e.target.value)})}/><b>{ocrCrop.scale}</b></label>
  </div>
  <div className="ocrPresets">
    <button onClick={()=>setOcrCrop({ x: 34, y: 0, w: 60, h: 12, threshold: 95, scale: 4 })}>Preset top-center</button>
    <button onClick={()=>setOcrCrop({ x: 0, y: 0, w: 100, h: 16, threshold: 95, scale: 4 })}>Preset full-top</button>
    <button onClick={()=>setOcrCrop({ x: 38, y: 0, w: 58, h: 9, threshold: 120, scale: 5 })}>Preset recursos</button>
  </div>
  <canvas ref={cropCanvasRef} width="1600" height="190" className="ocrCrop"/>
  <div className="row"><button onClick={runOcrTopBar} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer zona OCR"}</button><button onClick={runSegmentedOcr} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer por cajas"}</button><button onClick={applyOcrToResources}>Aplicar OCR simple</button><button onClick={applySegmentedOcrToResources}>Aplicar OCR por cajas</button></div>
  <p className="hint">Numeros detectados: {ocrNumbers.join(" / ") || "sin datos"}</p>
  <p className="hint">Tip: mueve X/Y/W/H hasta que el recorte muestre solo la barra de recursos, sin panel izquierdo ni mapa.</p>
  <div className="segmentedOcrGrid editable">
    {(ocrEditable || []).map((r) => (
      <div className="segOcrCard" key={r.key}>
        <strong>{r.label}</strong>
        <label>Stock<input value={r.stock} onChange={(e)=>updateOcrEditable(r.key, "stock", e.target.value)} /></label>
        <label>Hora<input value={r.hour} onChange={(e)=>updateOcrEditable(r.key, "hour", e.target.value)} /></label>
        <small>{r.raw || "sin lectura"}</small>
      </div>
    ))}
  </div>
  <textarea className="ocrText" value={ocrText} onChange={e=>{}} readOnly/>
</Panel>{captureOpen && <div className="captureModal"><div className="captureModalTop"><strong>LIVE GAME FEED</strong><div className="row"><button onClick={()=>setCaptureSize(captureSize==="compact"?"large":"compact")}>Tamano {captureSize}</button><button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button><button className="danger" onClick={()=>setCaptureOpen(false)}>Cerrar</button></div></div><div className="captureBigStage" onPointerDown={addMark}><canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig"/>{marks.map((m,i)=><div className="captureMark big" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}</div></div>}</section>;
}
function DataTab({ selected, patchSelected, games, persist }) {
  const [fronts,setFronts]=useState(JSON.stringify(selected.fronts||[],null,2)); const [research,setResearch]=useState((selected.research||[]).join(", ")); const [notes,setNotes]=useState(selected.notes||""); const [io,setIo]=useState("");
  useEffect(()=>{setFronts(JSON.stringify(selected.fronts||[],null,2));setResearch((selected.research||[]).join(", "));setNotes(selected.notes||"");},[selected.id]);
  function save(){patchSelected({fronts:JSON.parse(fronts),research:research.split(",").map(x=>x.trim()).filter(Boolean),notes});}
  return <section className="dataGrid"><Panel title="Datos de partida"><div className="formGrid three"><label>Frentes JSON<textarea value={fronts} onChange={e=>setFronts(e.target.value)}/></label><label>Research<textarea value={research} onChange={e=>setResearch(e.target.value)}/></label><label>Notas<textarea value={notes} onChange={e=>setNotes(e.target.value)}/></label></div><button onClick={save}>Guardar datos</button></Panel><Panel title="Import / Export JSON"><textarea value={io} onChange={e=>setIo(e.target.value)}/><div className="row"><button onClick={()=>setIo(JSON.stringify(games,null,2))}>Exportar</button><button onClick={()=>{const p=JSON.parse(io).map(normalizeGame); persist(p);}}>Importar</button></div></Panel></section>;
}
function Front({ f }) { return <div className="frontItem"><strong>{f.name}</strong><p>{f.state} - {f.action}</p><span>{f.risk}</span></div>; }

createRoot(document.getElementById("root")).render(<App/>);