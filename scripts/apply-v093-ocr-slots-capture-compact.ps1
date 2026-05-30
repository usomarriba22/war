
# CON War Room v0.9.3 — OCR Slots + Capture Compact
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

# 1. Añadir estado OCR editable + modo compacto
if ($main -notmatch 'const \[ocrEditable, setOcrEditable\]') {
  $main = $main.Replace(
    'const [segmentedOcr, setSegmentedOcr] = useState([]);',
    'const [segmentedOcr, setSegmentedOcr] = useState([]);' + "`r`n" +
    '  const [ocrEditable, setOcrEditable] = useState([]);' + "`r`n" +
    '  const [captureSize, setCaptureSize] = useState("compact");'
  )
}

# 2. Reemplazar runSegmentedOcr por versión que recorta zona de texto de cada caja y rellena editable
$rxSegmented = [regex]'async function runSegmentedOcr\(\) \{[\s\S]*?\n  \}\s*\n\s*function applySegmentedOcrToResources\(\) \{[\s\S]*?\n  \}'
$newSegmented = @'
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
'@

$main = $rxSegmented.Replace($main, $newSegmented, 1)

# 3. Pasar nuevos props a CaptureTab
$main = $main.Replace(
  'segmentedOcr={segmentedOcr} runSegmentedOcr={runSegmentedOcr} applySegmentedOcrToResources={applySegmentedOcrToResources} />',
  'segmentedOcr={segmentedOcr} ocrEditable={ocrEditable} updateOcrEditable={updateOcrEditable} runSegmentedOcr={runSegmentedOcr} applySegmentedOcrToResources={applySegmentedOcrToResources} captureSize={captureSize} setCaptureSize={setCaptureSize} />'
)

# 4. Cambiar firma de CaptureTab
$main = $main.Replace(
  'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop, segmentedOcr, runSegmentedOcr, applySegmentedOcrToResources })',
  'function CaptureTab({ videoRef, canvasRef, bigCanvasRef, cropCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, addMark, marks, setMarks, markLabel, setMarkLabel, runOcrTopBar, ocrBusy, ocrText, ocrNumbers, applyOcrToResources, ocrCrop, setOcrCrop, segmentedOcr, ocrEditable, updateOcrEditable, runSegmentedOcr, applySegmentedOcrToResources, captureSize, setCaptureSize })'
)

# 5. Compactar canvas con clase dinámica
$main = $main.Replace(
  '<div className="captureStage" onPointerDown={addMark}><canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/>',
  '<div className={`captureStage ${captureSize}`} onPointerDown={addMark}><canvas ref={canvasRef} width="1280" height="720" className="captureCanvas"/>'
)

# 6. Añadir botón tamaño antes de modo
$main = $main.Replace(
  '<button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button>',
  '<button onClick={()=>setCaptureSize(captureSize==="compact"?"large":"compact")}>Tamano {captureSize}</button><button onClick={()=>setCaptureMode(captureMode==="fit"?"fill":"fit")}>Modo {captureMode}</button>'
)

# 7. Reemplazar grid de segmented OCR cards por inputs editables
$oldGrid = @'
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
$newGrid = @'
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
'@

$main = $main.Replace($oldGrid, $newGrid)

# 8. CSS
$cssAppend = @'

/* v0.9.3 OCR editable slots + compact capture */
.captureStage.compact .captureCanvas {
  height: 430px;
}

.captureStage.large .captureCanvas {
  height: 620px;
}

.segmentedOcrGrid.editable {
  grid-template-columns: repeat(7, minmax(120px, 1fr));
}

.segOcrCard label {
  display: block;
  margin: 5px 0;
  color: #8fb4c7;
  font-size: 10px;
}

.segOcrCard input {
  margin-top: 3px;
  padding: 6px 7px;
  font-size: 12px;
  border-radius: 8px;
}

@media(max-width:1400px) {
  .segmentedOcrGrid.editable {
    grid-template-columns: repeat(2, 1fr);
  }
}
'@

if ($css -notmatch 'v0\.9\.3 OCR editable slots') {
  $css = $css + $cssAppend
}

[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $main, $Utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)

Write-Host "v0.9.3 OCR Slots + Capture Compact aplicado."
Write-Host "Siguiente: git add . ; git commit ; git push ; build web ; rollout restart."
