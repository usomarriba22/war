
# CON War Room v0.8.2 — UX Fix + OCR Prep + Movement Map Overlay
# Ejecutar desde VS Code PowerShell en:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$mainPath = ".\02-apps\warroom-web\src\main.jsx"
$cssPath = ".\02-apps\warroom-web\src\styles.css"
$dataPath = ".\02-apps\warroom-web\src\lib\data.js"

$main = [System.IO.File]::ReadAllText((Resolve-Path $mainPath))

# 1) Reemplazar emojis por iconos simples, legibles y consistentes.
$main = $main -replace '<span>\{meta.icon\}</span>\{meta.label\}', '<span className="resIconText">{meta.short}</span>{meta.label}'

# 2) Mejorar copy del capture para dejar claro que NO puede controlar el juego, pero sí marcar objetivos.
$main = $main -replace 'Captura solo observa\. No mueve ni hace clicks\. v0\.9 añadira OCR calibrado\.', 'Captura solo observa. Por seguridad del navegador no puede mandar clicks al juego. Usa marcadores tacticos sobre el canvas para indicar unidades/objetivos; v0.9 añadira OCR calibrado.'

# 3) Añadir estado de marcadores en App.
if ($main -notmatch 'const \[captureMarks, setCaptureMarks\]') {
  $main = $main -replace 'const \[captureStatus, setCaptureStatus\] = useState\("offline"\);', 'const [captureStatus, setCaptureStatus] = useState("offline");' + "`r`n" + '  const [captureMarks, setCaptureMarks] = useState([]);'
}

# 4) Pasar props de marcadores al CaptureTab.
$main = $main -replace 'drawCapture=\{drawCapture\}\s*/>', 'drawCapture={drawCapture}' + "`r`n" + '            captureMarks={captureMarks}' + "`r`n" + '            setCaptureMarks={setCaptureMarks}' + "`r`n" + '          />'

# 5) Reemplazar la firma de CaptureTab.
$main = $main -replace 'function CaptureTab\(\{ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture \}\)', 'function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks })'

# 6) Inyectar funciones de marcadores dentro de CaptureTab.
if ($main -notmatch 'function addCaptureMark') {
  $main = $main -replace 'function CaptureTab\(\{ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks \}\) \{', @'
function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks }) {
  function addCaptureMark(e) {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * 100;
    const y = ((e.clientY - rect.top) / rect.height) * 100;
    const label = prompt("Marcador tactico: unidad, ciudad, enemigo u objetivo", "objetivo");
    if (!label) return;
    setCaptureMarks([...(captureMarks || []), { x, y, label, type: "point", time: new Date().toISOString() }]);
  }

  function clearCaptureMarks() {
    setCaptureMarks([]);
  }
'@
}

# 7) Envolver canvas preview en contenedor con overlay clicable.
$oldCanvas = '<canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas" />'
$newCanvas = @'
<div className="captureStage" onDoubleClick={addCaptureMark}>
          <canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas" />
          {(captureMarks || []).map((m, i) => (
            <div className="captureMark" key={i} style={{ left: `${m.x}%`, top: `${m.y}%` }}>
              <span>{i + 1}</span>
              <em>{m.label}</em>
            </div>
          ))}
        </div>
'@
$main = $main.Replace($oldCanvas, $newCanvas)

# 8) Añadir botones de marcadores.
$main = $main -replace '<button onClick=\{\(\) => setCaptureMode\(captureMode === "fit" \? "fill" : "fit"\)\}>Modo \{captureMode\}</button>\s*<button className="danger" onClick=\{stopCapture\}>Parar</button>', @'
<button onClick={() => setCaptureMode(captureMode === "fit" ? "fill" : "fit")}>Modo {captureMode}</button>
          <button onClick={clearCaptureMarks}>Limpiar marcas</button>
          <button className="danger" onClick={stopCapture}>Parar</button>
'@

# 9) Reemplazar canvas grande por stage con overlay.
$oldBig = '<canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig" />'
$newBig = @'
<div className="captureBigStage" onDoubleClick={addCaptureMark}>
            <canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig" />
            {(captureMarks || []).map((m, i) => (
              <div className="captureMark big" key={i} style={{ left: `${m.x}%`, top: `${m.y}%` }}>
                <span>{i + 1}</span>
                <em>{m.label}</em>
              </div>
            ))}
          </div>
'@
$main = $main.Replace($oldBig, $newBig)

# 10) Mejorar titulo de CaptureTab.
$main = $main -replace '<Panel title="Capture Center" right=\{captureStatus\} icon=\{<Video size=\{16\}/>\}>', '<Panel title="Capture Center + Tactical Markers" right={captureStatus} icon={<Video size={16}/>}>'

[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $main, $Utf8NoBom)

# 11) Actualizar data.js para usar short text en vez de emojis.
$data = [System.IO.File]::ReadAllText((Resolve-Path $dataPath))
$data = $data -replace 'supplies: \{ label: "Supplies", icon: "📦", target: 5000 \}', 'supplies: { label: "Supplies", icon: "📦", short: "SUP", target: 5000 }'
$data = $data -replace 'components: \{ label: "Components", icon: "⚙️", target: 4500 \}', 'components: { label: "Components", icon: "⚙️", short: "CMP", target: 4500 }'
$data = $data -replace 'fuel: \{ label: "Fuel", icon: "⛽", target: 3500 \}', 'fuel: { label: "Fuel", icon: "⛽", short: "FUL", target: 3500 }'
$data = $data -replace 'electronics: \{ label: "Electronics", icon: "🔌", target: 2500 \}', 'electronics: { label: "Electronics", icon: "🔌", short: "ELC", target: 2500 }'
$data = $data -replace 'rares: \{ label: "Rares", icon: "💎", target: 1800 \}', 'rares: { label: "Rares", icon: "💎", short: "RAR", target: 1800 }'
$data = $data -replace 'manpower: \{ label: "Manpower", icon: "🪖", target: 3000 \}', 'manpower: { label: "Manpower", icon: "🪖", short: "MAN", target: 3000 }'
$data = $data -replace 'money: \{ label: "Money", icon: "💵", target: 20000 \}', 'money: { label: "Money", icon: "💵", short: "MON", target: 20000 }'
[System.IO.File]::WriteAllText((Resolve-Path $dataPath), $data, $Utf8NoBom)

# 12) CSS UX: letras mas limpias, iconos visibles, capture stage con marcadores.
$css = [System.IO.File]::ReadAllText((Resolve-Path $cssPath))

$append = @'

/* v0.8.2 UX readability + capture tactical markers */
.resourceTop strong {
  font-size: 14px;
  letter-spacing: .8px;
}

.resIconText {
  width: 38px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(54,217,255,.35);
  border-radius: 10px;
  background: rgba(54,217,255,.12);
  color: #36d9ff;
  font-size: 11px;
  font-weight: 950;
  font-family: Consolas, monospace;
  box-shadow: 0 0 14px rgba(54,217,255,.16);
}

.resourceCard {
  min-height: 160px;
}

.captureStage,
.captureBigStage {
  position: relative;
  width: 100%;
  background: #000;
  border-radius: 18px;
  overflow: hidden;
  border: 1px solid rgba(54,217,255,.25);
}

.captureCanvas,
.captureBig {
  border: 0 !important;
  border-radius: 0 !important;
}

.captureMark {
  position: absolute;
  transform: translate(-50%, -50%);
  display: flex;
  align-items: center;
  gap: 7px;
  pointer-events: none;
  filter: drop-shadow(0 0 8px rgba(61,255,155,.65));
}

.captureMark span {
  width: 26px;
  height: 26px;
  border-radius: 999px;
  background: rgba(61,255,155,.18);
  border: 1px solid #3dff9b;
  color: #3dff9b;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 950;
}

.captureMark em {
  font-style: normal;
  font-size: 12px;
  color: #d8f3ff;
  background: rgba(0,0,0,.72);
  border: 1px solid rgba(54,217,255,.35);
  border-radius: 999px;
  padding: 5px 8px;
}

.captureMark.big span {
  width: 34px;
  height: 34px;
}

.captureMark.big em {
  font-size: 14px;
}

.panel,
.metricCard,
.resourceCard,
.frontItem,
.feedItem,
.moveCard {
  backdrop-filter: blur(8px);
}

.hint {
  line-height: 1.45;
}
'@

if ($css -notmatch 'v0\.8\.2 UX readability') {
  $css = $css + $append
}

[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)

Write-Host "v0.8.2 UX/OCR/Movement marker patch aplicado."
Write-Host "Ahora ejecuta: git add . ; git commit ; git push ; gh workflow run Build warroom-web ; rollout restart."
