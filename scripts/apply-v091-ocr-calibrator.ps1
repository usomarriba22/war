
# CON War Room v0.9.1 — OCR Calibrator Patch
# Ejecutar desde VS Code PowerShell en:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$mainPath = ".\02-apps\warroom-web\src\main.jsx"
$cssPath  = ".\02-apps\warroom-web\src\styles.css"

if (!(Test-Path $mainPath)) { throw "No existe $mainPath" }
if (!(Test-Path $cssPath)) { throw "No existe $cssPath" }

$main = [System.IO.File]::ReadAllText((Resolve-Path $mainPath))
$css  = [System.IO.File]::ReadAllText((Resolve-Path $cssPath))

# 1. Estado del calibrador OCR
if ($main -notmatch 'const \[ocrCrop, setOcrCrop\]') {
  $main = $main.Replace(
    'const [ocrBusy, setOcrBusy] = useState(false);',
    'const [ocrBusy, setOcrBusy] = useState(false);' + "`r`n" +
    '  const [ocrCrop, setOcrCrop] = useState({ x: 34, y: 0, w: 60, h: 12, threshold: 95, scale: 4 });'
  )
}

# 2. Reemplazar runOcrTopBar por versión calibrable
$rxRunOcr = [regex]'async function runOcrTopBar\(\) \{[\s\S]*?\n  \}'
$newRunOcr = @'
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
'@
$main = $rxRunOcr.Replace($main, $newRunOcr, 1)

# 3. Pasar props OCR calibrator a CaptureTab
$main = $main.Replace(
  'ocrNumbers={ocrNumbers} applyOcrToResources={applyOcrToResources} />',
  'ocrNumbers={ocrNumbers} applyOcrToResources={applyOcrToResources} ocrCrop={ocrCrop} setOcrCrop={setOcrCrop} />'
)

# 4. Cambiar firma CaptureTab
$main = $main.Replace(
  'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources })',
  'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop })'
)

# 5. Meter overlay visual de zona OCR sobre la captura
$main = $main.Replace(
  '<canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/>{marks.map((m,i)=><div className="captureMark" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}',
  '<canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/><div className="ocrBoxOverlay" style={{ left: `${ocrCrop.x}%`, top: `${ocrCrop.y}%`, width: `${ocrCrop.w}%`, height: `${ocrCrop.h}%` }}><span>OCR TOP BAR</span></div>{marks.map((m,i)=><div className="captureMark" key={i} style={{left:`${m.x}%`,top:`${m.y}%`}}><span>{i+1}</span><em>{m.label}</em></div>)}'
)

# 6. Añadir controles OCR antes del canvas crop
$oldOcrPanel = '<Panel title="OCR Top Bar"><canvas ref={cropCanvasRef} width="1600" height="190" className="ocrCrop"/><div className="row"><button onClick={runOcrTopBar} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer barra superior"}</button><button onClick={applyOcrToResources}>Aplicar OCR a recursos</button></div><p className="hint">Numeros detectados: {ocrNumbers.join(" / ") || "sin datos"}</p><textarea className="ocrText" value={ocrText} onChange={e=>{}} readOnly/></Panel>'
$newOcrPanel = @'
<Panel title="OCR Top Bar Calibrator">
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
  <div className="row"><button onClick={runOcrTopBar} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer zona OCR"}</button><button onClick={applyOcrToResources}>Aplicar OCR a recursos</button></div>
  <p className="hint">Numeros detectados: {ocrNumbers.join(" / ") || "sin datos"}</p>
  <p className="hint">Tip: mueve X/Y/W/H hasta que el recorte muestre solo la barra de recursos, sin panel izquierdo ni mapa.</p>
  <textarea className="ocrText" value={ocrText} onChange={e=>{}} readOnly/>
</Panel>
'@
$main = $main.Replace($oldOcrPanel, $newOcrPanel)

# 7. Mejorar parseOcrNumbers para no quedarse con 0/0/230 del panel izquierdo
$main = $main.Replace(
  'return nums.map(n => Number(n.replace(/[.,]/g, ""))).filter(n => Number.isFinite(n) && n >= 0);',
  'return nums.map(n => Number(n.replace(/[.,]/g, ""))).filter(n => Number.isFinite(n) && n >= 10);'
)

# 8. CSS
$cssAppend = @'

/* v0.9.1 OCR calibrator */
.ocrControls {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin-bottom: 10px;
}

.ocrControls label {
  border: 1px solid rgba(54,217,255,.18);
  border-radius: 12px;
  padding: 8px;
  background: rgba(255,255,255,.03);
}

.ocrControls input[type="range"] {
  padding: 0;
  margin-top: 8px;
}

.ocrControls b {
  display: inline-block;
  margin-left: 8px;
  color: #3dff9b;
}

.ocrPresets {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 10px;
}

.ocrBoxOverlay {
  position: absolute;
  border: 2px dashed #3dff9b;
  background: rgba(61,255,155,.08);
  box-shadow: 0 0 16px rgba(61,255,155,.25);
  pointer-events: none;
  z-index: 3;
}

.ocrBoxOverlay span {
  position: absolute;
  top: -24px;
  left: 0;
  background: rgba(0,0,0,.75);
  color: #3dff9b;
  border: 1px solid rgba(61,255,155,.45);
  border-radius: 999px;
  padding: 4px 8px;
  font-size: 11px;
  font-weight: 900;
  letter-spacing: .8px;
}

.ocrCrop {
  height: 160px;
  object-fit: contain;
}
'@

if ($css -notmatch 'v0\.9\.1 OCR calibrator') {
  $css = $css + $cssAppend
}

[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $main, $Utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)

Write-Host "v0.9.1 OCR Calibrator aplicado."
Write-Host "Siguiente: git add . ; git commit ; git push ; build web ; rollout restart."
