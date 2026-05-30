Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$mainPath = ".\02-apps\warroom-web\src\main.jsx"
$cssPath  = ".\02-apps\warroom-web\src\styles.css"
$dataPath = ".\02-apps\warroom-web\src\lib\data.js"

if (!(Test-Path $mainPath)) { throw "No existe main.jsx: $mainPath" }
if (!(Test-Path $cssPath))  { throw "No existe styles.css: $cssPath" }
if (!(Test-Path $dataPath)) { throw "No existe data.js: $dataPath" }

$main = [System.IO.File]::ReadAllText((Resolve-Path $mainPath))
$css  = [System.IO.File]::ReadAllText((Resolve-Path $cssPath))
$data = [System.IO.File]::ReadAllText((Resolve-Path $dataPath))

# RESOURCE_META sin emojis, para que se vea limpio
$resourceMetaLines = @(
  'export const RESOURCE_META = {',
  '  supplies: { label: "Supplies", short: "SUP", target: 5000 },',
  '  components: { label: "Components", short: "CMP", target: 4500 },',
  '  fuel: { label: "Fuel", short: "FUL", target: 3500 },',
  '  electronics: { label: "Electronics", short: "ELC", target: 2500 },',
  '  rares: { label: "Rares", short: "RAR", target: 1800 },',
  '  manpower: { label: "Manpower", short: "MAN", target: 3000 },',
  '  money: { label: "Money", short: "MON", target: 20000 }',
  '};'
)

$resourceMeta = $resourceMetaLines -join "`n"

$rx = New-Object System.Text.RegularExpressions.Regex(
  'export const RESOURCE_META = \{[\s\S]*?\};',
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$data = $rx.Replace($data, $resourceMeta)

# Recurso visual: usar SUP/CMP/FUL/etc en vez de emoji roto
$main = $main.Replace(
  '<strong><span>{meta.icon}</span>{meta.label}</strong>',
  '<strong><span className="resIconText">{meta.short}</span>{meta.label}</strong>'
)

# Estado para marcadores tacticos
if ($main -notmatch 'captureMarks') {
  $main = $main.Replace(
    'const [captureStatus, setCaptureStatus] = useState("offline");',
    'const [captureStatus, setCaptureStatus] = useState("offline");' + "`r`n" +
    '  const [captureMarks, setCaptureMarks] = useState([]);'
  )
}

# Pasar props al CaptureTab
$main = [regex]::Replace(
  $main,
  'drawCapture=\{drawCapture\}\s*/>',
  'drawCapture={drawCapture}' + "`r`n" +
  '            captureMarks={captureMarks}' + "`r`n" +
  '            setCaptureMarks={setCaptureMarks}' + "`r`n" +
  '          />'
)

# Firma de CaptureTab
$main = $main.Replace(
  'function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture })',
  'function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks })'
)

# Funciones de marcadores
if ($main -notmatch 'function addCaptureMark') {
  $main = $main.Replace(
    'function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks }) {',
    'function CaptureTab({ videoRef, previewCanvasRef, bigCanvasRef, captureOpen, setCaptureOpen, captureStatus, captureMode, setCaptureMode, startCapture, stopCapture, drawCapture, captureMarks, setCaptureMarks }) {' + "`r`n" +
    '  function addCaptureMark(e) {' + "`r`n" +
    '    const rect = e.currentTarget.getBoundingClientRect();' + "`r`n" +
    '    const x = ((e.clientX - rect.left) / rect.width) * 100;' + "`r`n" +
    '    const y = ((e.clientY - rect.top) / rect.height) * 100;' + "`r`n" +
    '    const label = prompt("Marcador tactico: unidad, enemigo, ciudad u objetivo", "objetivo");' + "`r`n" +
    '    if (!label) return;' + "`r`n" +
    '    setCaptureMarks([...(captureMarks || []), { x, y, label, time: new Date().toISOString() }]);' + "`r`n" +
    '  }' + "`r`n`r`n" +
    '  function clearCaptureMarks() {' + "`r`n" +
    '    setCaptureMarks([]);' + "`r`n" +
    '  }'
  )
}

# Canvas preview con overlay de marcadores
$main = $main.Replace(
  '<canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas" />',
  '<div className="captureStage" onDoubleClick={addCaptureMark}>' + "`r`n" +
  '          <canvas ref={previewCanvasRef} width="1280" height="720" className="captureCanvas" />' + "`r`n" +
  '          {(captureMarks || []).map((m, i) => (' + "`r`n" +
  '            <div className="captureMark" key={i} style={{ left: `${m.x}%`, top: `${m.y}%` }}>' + "`r`n" +
  '              <span>{i + 1}</span>' + "`r`n" +
  '              <em>{m.label}</em>' + "`r`n" +
  '            </div>' + "`r`n" +
  '          ))}' + "`r`n" +
  '        </div>'
)

# Boton limpiar marcas
$main = $main.Replace(
  '<button onClick={() => setCaptureMode(captureMode === "fit" ? "fill" : "fit")}>Modo {captureMode}</button>' + "`r`n" +
  '          <button className="danger" onClick={stopCapture}>Parar</button>',
  '<button onClick={() => setCaptureMode(captureMode === "fit" ? "fill" : "fit")}>Modo {captureMode}</button>' + "`r`n" +
  '          <button onClick={clearCaptureMarks}>Limpiar marcas</button>' + "`r`n" +
  '          <button className="danger" onClick={stopCapture}>Parar</button>'
)

# Canvas grande con overlay
$main = $main.Replace(
  '<canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig" />',
  '<div className="captureBigStage" onDoubleClick={addCaptureMark}>' + "`r`n" +
  '            <canvas ref={bigCanvasRef} width="1920" height="1080" className="captureBig" />' + "`r`n" +
  '            {(captureMarks || []).map((m, i) => (' + "`r`n" +
  '              <div className="captureMark big" key={i} style={{ left: `${m.x}%`, top: `${m.y}%` }}>' + "`r`n" +
  '                <span>{i + 1}</span>' + "`r`n" +
  '                <em>{m.label}</em>' + "`r`n" +
  '              </div>' + "`r`n" +
  '            ))}' + "`r`n" +
  '          </div>'
)

$cssAppend = @(
  '',
  '/* v0.8.3 safe UX patch */',
  '.resIconText {',
  '  width: 38px;',
  '  height: 28px;',
  '  display: inline-flex;',
  '  align-items: center;',
  '  justify-content: center;',
  '  border: 1px solid rgba(54,217,255,.35);',
  '  border-radius: 10px;',
  '  background: rgba(54,217,255,.12);',
  '  color: #36d9ff;',
  '  font-size: 11px;',
  '  font-weight: 950;',
  '  font-family: Consolas, monospace;',
  '  box-shadow: 0 0 14px rgba(54,217,255,.16);',
  '}',
  '',
  '.resourceTop strong {',
  '  font-size: 14px;',
  '  letter-spacing: .8px;',
  '}',
  '',
  '.resourceCard { min-height: 160px; }',
  '',
  '.captureStage, .captureBigStage {',
  '  position: relative;',
  '  width: 100%;',
  '  background: #000;',
  '  border-radius: 18px;',
  '  overflow: hidden;',
  '  border: 1px solid rgba(54,217,255,.25);',
  '}',
  '',
  '.captureCanvas, .captureBig {',
  '  border: 0 !important;',
  '  border-radius: 0 !important;',
  '}',
  '',
  '.captureMark {',
  '  position: absolute;',
  '  transform: translate(-50%, -50%);',
  '  display: flex;',
  '  align-items: center;',
  '  gap: 7px;',
  '  pointer-events: none;',
  '  filter: drop-shadow(0 0 8px rgba(61,255,155,.65));',
  '}',
  '',
  '.captureMark span {',
  '  width: 26px;',
  '  height: 26px;',
  '  border-radius: 999px;',
  '  background: rgba(61,255,155,.18);',
  '  border: 1px solid #3dff9b;',
  '  color: #3dff9b;',
  '  display: inline-flex;',
  '  align-items: center;',
  '  justify-content: center;',
  '  font-weight: 950;',
  '}',
  '',
  '.captureMark em {',
  '  font-style: normal;',
  '  font-size: 12px;',
  '  color: #d8f3ff;',
  '  background: rgba(0,0,0,.72);',
  '  border: 1px solid rgba(54,217,255,.35);',
  '  border-radius: 999px;',
  '  padding: 5px 8px;',
  '}',
  '',
  '.captureMark.big span { width: 34px; height: 34px; }',
  '.captureMark.big em { font-size: 14px; }',
  '.hint { line-height: 1.45; }'
) -join "`n"

if ($css -notmatch 'v0.8.3 safe UX patch') {
  $css = $css + $cssAppend
}

[System.IO.File]::WriteAllText((Resolve-Path $mainPath), $main, $Utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path $cssPath), $css, $Utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path $dataPath), $data, $Utf8NoBom)

Write-Host "v0.8.3 safe patch aplicado correctamente."