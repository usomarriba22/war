
# CON War Room v0.9.2 — Segmented OCR Patch
# Ejecutar desde VS Code PowerShell:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$mainPath = ".\02-apps\warroom-web\src\main.jsx"
$cssPath  = ".\02-apps\warroom-web\src\styles.css"

if (!(Test-Path $mainPath)) { throw "No existe $mainPath" }
if (!(Test-Path $cssPath)) { throw "No existe $cssPath" }

$main = [System.IO.File]::ReadAllText((Resolve-Path $mainPath))
$css  = [System.IO.File]::ReadAllText((Resolve-Path $cssPath))

# 1. Estado para OCR por segmentos
if ($main -notmatch 'const \[segmentedOcr, setSegmentedOcr\]') {
  $main = $main.Replace(
    'const [ocrNumbers, setOcrNumbers] = useState([]);',
    'const [ocrNumbers, setOcrNumbers] = useState([]);' + "`r`n" +
    '  const [segmentedOcr, setSegmentedOcr] = useState([]);'
  )
}

# 2. Insertar funciones segmented OCR despues de applyOcrToResources
if ($main -notmatch 'async function runSegmentedOcr') {
  $marker = @'
  function applyOcrToResources() {
    if (ocrNumbers.length < 7) return alert("OCR no detecto 7 numeros. Ajusta captura/zoom y prueba otra vez.");
    const resources = { ...selected.resources };
    RESOURCE_KEYS.forEach((key, i) => {
      const value = ocrNumbers[i];
      resources[key] = { ...resources[key], value, status: deriveStatus(key, value) };
    });
    replaceSelected(addFeed({ ...selected, resources, live_base_at: nowIso() }, "OCR aplicado a recursos", "info"));
  }
'@

  $insert = @'
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

        const segCanvas = document.createElement("canvas");
        const segW = Math.round(sw / RESOURCE_KEYS.length);
        const padding = Math.round(segW * 0.05);
        const realSx = sx + (i * segW) + padding;
        const realSw = Math.max(10, segW - (padding * 2));

        segCanvas.width = Math.max(260, realSw * Number(ocrCrop.scale || 5));
        segCanvas.height = Math.max(140, sh * Number(ocrCrop.scale || 5));

        const ctx = segCanvas.getContext("2d");
        ctx.imageSmoothingEnabled = false;
        ctx.fillStyle = "#000";
        ctx.fillRect(0, 0, segCanvas.width, segCanvas.height);
        ctx.drawImage(src, realSx, sy, realSw, sh, 0, 0, segCanvas.width, segCanvas.height);

        const img = ctx.getImageData(0, 0, segCanvas.width, segCanvas.height);
        const threshold = Number(ocrCrop.threshold || 110);

        for (let p = 0; p < img.data.length; p += 4) {
          const r = img.data[p];
          const g = img.data[p + 1];
          const b = img.data[p + 2];
          const brightness = (r + g + b) / 3;
          const greenBoost = g > r + 10 && g > b + 10 ? 45 : 0;
          const whiteBoost = r > 150 && g > 150 && b > 150 ? 35 : 0;
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
        const stock = nums[0] ?? null;
        const hour = nums[1] ?? null;

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
      setOcrText(results.map(r => `${r.label}: ${r.text.replace(/\s+/g, " ").trim()} => ${r.nums.join(" / ")}`).join("\n"));
      setOcrNumbers(results.map(r => r.stock).filter(n => n !== null));
    } catch (e) {
      setOcrText(`Segmented OCR error: ${e.message}`);
    }
    setOcrBusy(false);
  }

  function applySegmentedOcrToResources() {
    if (!segmentedOcr || segmentedOcr.length < 7) {
      return alert("Primero ejecuta OCR por cajas.");
    }

    const resources = { ...selected.resources };

    segmentedOcr.forEach((item) => {
      if (!item || !item.key) return;
      const current = resources[item.key] || {};
      const next = { ...current };

      if (item.stock !== null && item.stock !== undefined) {
        next.value = Number(item.stock);
        next.status = deriveStatus(item.key, next.value);
      }

      if (item.hour !== null && item.hour !== undefined) {
        next.hour = Number(item.hour);
      }

      resources[item.key] = next;
    });

    replaceSelected(addFeed({ ...selected, resources, live_base_at: nowIso() }, "OCR por cajas aplicado a recursos", "info"));
  }
'@

  if ($main.Contains($marker)) {
    $main = $main.Replace($marker, $insert)
  } else {
    throw "No se encontro bloque applyOcrToResources esperado. No aplico parche."
  }
}

# 3. Pasar props a CaptureTab
$oldProps = 'ocrNumbers={ocrNumbers} applyOcrToResources={applyOcrToResources} ocrCrop={ocrCrop} setOcrCrop={setOcrCrop} />'
$newProps = 'ocrNumbers={ocrNumbers} applyOcrToResources={applyOcrToResources} ocrCrop={ocrCrop} setOcrCrop={setOcrCrop} segmentedOcr={segmentedOcr} runSegmentedOcr={runSegmentedOcr} applySegmentedOcrToResources={applySegmentedOcrToResources} />'
$main = $main.Replace($oldProps, $newProps)

# 4. Cambiar firma de CaptureTab
$oldSig = 'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop })'
$newSig = 'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop, segmentedOcr, runSegmentedOcr, applySegmentedOcrToResources })'
$main = $main.Replace($oldSig, $newSig)

# 5. Reemplazar row de OCR con botones nuevos
$oldRow = '<div className="row"><button onClick={runOcrTopBar} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer zona OCR"}</button><button onClick={applyOcrToResources}>Aplicar OCR a recursos</button></div>'
$newRow = '<div className="row"><button onClick={runOcrTopBar} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer zona OCR"}</button><button onClick={runSegmentedOcr} disabled={ocrBusy}>{ocrBusy ? "OCR..." : "Leer por cajas"}</button><button onClick={applyOcrToResources}>Aplicar OCR simple</button><button onClick={applySegmentedOcrToResources}>Aplicar OCR por cajas</button></div>'
$main = $main.Replace($oldRow, $newRow)

# 6. Insertar tabla de resultados por caja antes del texto OCR
$oldHint = '<p className="hint">Tip: mueve X/Y/W/H hasta que el recorte muestre solo la barra de recursos, sin panel izquierdo ni mapa.</p>'
$newHint = @'
<p className="hint">Tip: mueve X/Y/W/H hasta que el recorte muestre solo la barra de recursos, sin panel izquierdo ni mapa.</p>
  <div className="segmentedOcrGrid">
    {(segmentedOcr || []).map((r) => (
      <div className="segOcrCard" key={r.key}>
        <strong>{r.label}</strong>
        <span>Stock: {r.stock ?? "?"}</span>
        <span>Hora: {r.hour ?? "?"}</span>
        <small>{(r.text || "").replace(/\s+/g, " ").slice(0, 80)}</small>
      </div>
    ))}
  </div>
'@
$main = $main.Replace($oldHint, $newHint)

# 7. CSS
$cssAppend = @'

/* v0.9.2 segmented OCR */
.segmentedOcrGrid {
  display: grid;
  grid-template-columns: repeat(7, minmax(90px, 1fr));
  gap: 8px;
  margin: 10px 0;
}

.segOcrCard {
  border: 1px solid rgba(54,217,255,.22);
  background: rgba(54,217,255,.055);
  border-radius: 12px;
  padding: 8px;
  min-height: 92px;
}

.segOcrCard strong {
  display: block;
  color: #36d9ff;
  font-size: 11px;
  text-transform: uppercase;
  margin-bottom: 5px;
}

.segOcrCard span {
  display: block;
  color: #d8f3ff;
  font-size: 12px;
  font-weight: 800;
}

.segOcrCard small {
  display: block;
  margin-top: 5px;
  color: #8fb4c7;
  font-size: 10px;
  word-break: break-word;
}

@media(max-width:1400px) {
  .segmentedOcrGrid {
    grid-template-columns: repeat(2, 1fr);
  }
}
'@

if ($css -notmatch 'v0\.9\.2 segmented OCR') {
  $css = $css + $cssAppend
}

[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $main, $Utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)

Write-Host "v0.9.2 Segmented OCR aplicado."
Write-Host "Siguiente: git add . ; git commit ; git push ; build web ; rollout restart."
