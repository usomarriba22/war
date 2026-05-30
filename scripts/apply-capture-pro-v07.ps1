
# CON War Room v0.7 Capture Pro Patch
# Ejecutar desde: C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"

$indexPath = ".\02-apps\warroom-web\public\index.html"
$html = Get-Content $indexPath -Raw

# 1) CSS Capture Pro: preview único, modal grande, overlay HUD.
$css = @'
<style id="capture-pro-v07-style">
.capture-box {
  border: 1px dashed rgba(54,217,255,.28);
  border-radius: 16px;
  padding: 10px;
  background: rgba(255,255,255,.025);
}

#captureVideo {
  display: none !important;
}

#captureCanvas {
  width: 100%;
  height: 260px;
  background:
    radial-gradient(circle at 50% 50%, rgba(54,217,255,.08), transparent 55%),
    #000;
  border: 1px solid rgba(54,217,255,.24);
  border-radius: 14px;
  object-fit: contain;
}

.capture-tools {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
  margin-top: 10px;
}

.capture-tools button {
  width: 100%;
}

.capture-status-line {
  margin-top: 8px;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.35;
}

.capture-modal {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background:
    radial-gradient(circle at 20% 20%, rgba(54,217,255,.14), transparent 28%),
    rgba(0,0,0,.88);
  display: none;
  padding: 24px;
}

.capture-modal.open {
  display: grid;
  grid-template-rows: auto 1fr auto;
  gap: 12px;
}

.capture-modal-header,
.capture-modal-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border: 1px solid rgba(54,217,255,.24);
  background: rgba(5,15,25,.88);
  border-radius: 16px;
  padding: 12px;
}

.capture-modal-title {
  font-weight: 950;
  letter-spacing: 2px;
  text-transform: uppercase;
  color: var(--cyan);
}

.capture-modal-body {
  position: relative;
  border: 1px solid rgba(54,217,255,.24);
  border-radius: 18px;
  background: #000;
  overflow: hidden;
  box-shadow: 0 0 60px rgba(54,217,255,.12);
}

#captureCanvasBig {
  width: 100%;
  height: 100%;
  display: block;
  background: #000;
  object-fit: contain;
}

.capture-hud {
  position: absolute;
  left: 16px;
  top: 16px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  pointer-events: none;
}

.capture-hud span {
  border: 1px solid rgba(54,217,255,.28);
  background: rgba(0,0,0,.55);
  color: var(--green);
  border-radius: 999px;
  padding: 7px 10px;
  font-size: 12px;
  font-weight: 900;
}

.capture-crosshair {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(90deg, transparent calc(50% - 1px), rgba(54,217,255,.18) 50%, transparent calc(50% + 1px)),
    linear-gradient(0deg, transparent calc(50% - 1px), rgba(54,217,255,.18) 50%, transparent calc(50% + 1px));
  opacity: .45;
}

.capture-scanline {
  position: absolute;
  left: 0; right: 0;
  top: var(--scanY, 0%);
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--green), transparent);
  box-shadow: 0 0 18px var(--green);
  pointer-events: none;
}

.zoom-badge {
  color: var(--amber);
  font-weight: 900;
}
</style>
'@

if ($html -notmatch 'capture-pro-v07-style') {
  $html = $html -replace '</head>', "$css`r`n</head>"
}

# 2) Sustituir el bloque de Captura Live completo.
$oldBlockRegex = '(?s)<section class="panel">\s*<div class="panel-title"><h2>Captura Live</h2>.*?</section>'

$newBlock = @'
<section class="panel">
  <div class="panel-title"><h2>Captura Live</h2><span class="mini" id="captureState">offline</span></div>
  <div class="capture-box">
    <video id="captureVideo" autoplay muted playsinline></video>
    <canvas id="captureCanvas" width="960" height="420"></canvas>

    <div class="capture-tools">
      <button onclick="startCapture()">Conectar pantalla</button>
      <button onclick="openCaptureModal()">Ampliar</button>
      <button onclick="toggleCaptureFit()">Fit / Fill</button>
      <button onclick="stopCapture()">Parar</button>
    </div>

    <div class="capture-status-line">
      Preview único: ya no se duplica video + canvas. La imagen se renderiza solo en canvas.
      Modo ampliado disponible. OCR/calibración en siguiente fase.
    </div>
  </div>
</section>
'@

if ($html -match $oldBlockRegex) {
  $html = [regex]::Replace($html, $oldBlockRegex, $newBlock, 1)
}

# 3) Añadir modal antes de cierre del body.
$modal = @'
<div class="capture-modal" id="captureModal">
  <div class="capture-modal-header">
    <div>
      <div class="capture-modal-title">CON WAR ROOM — LIVE GAME FEED</div>
      <div class="mini">Vista ampliada. Solo visualización; el navegador no puede enviar clicks al juego capturado.</div>
    </div>
    <div class="row">
      <span class="zoom-badge" id="captureZoomState">FIT</span>
      <button onclick="toggleCaptureFit()">Fit / Fill</button>
      <button class="danger" onclick="closeCaptureModal()">Cerrar</button>
    </div>
  </div>

  <div class="capture-modal-body">
    <canvas id="captureCanvasBig" width="1920" height="1080"></canvas>
    <div class="capture-hud">
      <span id="captureHudState">OFFLINE</span>
      <span id="captureHudFps">FPS --</span>
      <span id="captureHudGame">PARTIDA SELECCIONADA</span>
    </div>
    <div class="capture-crosshair"></div>
    <div class="capture-scanline" id="captureScanline"></div>
  </div>

  <div class="capture-modal-footer">
    <div class="mini">
      Consejo: deja CON en una ventana y el War Room en otra. Captura la ventana del juego y usa Alt+Tab para jugar normal.
    </div>
    <div class="row">
      <button onclick="manualSnapshot()">Snapshot</button>
      <button onclick="askAdvisor()">Ask Advisor</button>
    </div>
  </div>
</div>
'@

if ($html -notmatch 'captureModal') {
  $html = $html -replace '</body>', "$modal`r`n</body>"
}

# 4) Reemplazar funciones de captura por versión v0.7.
$functionsRegex = '(?s)async function startCapture\(\).*?function sampleCaptureFrame\(\).*?\n\}'

$newFunctions = @'
let captureFitMode = "fit";
let captureFrameCounter = 0;
let captureLastFpsAt = Date.now();
let captureFps = 0;
let captureDrawTimer = null;

async function startCapture() {
  try {
    captureStream = await navigator.mediaDevices.getDisplayMedia({
      video: {
        frameRate: { ideal: 30, max: 60 },
        width: { ideal: 1920 },
        height: { ideal: 1080 }
      },
      audio: false
    });

    const video = document.getElementById("captureVideo");
    video.srcObject = captureStream;
    video.style.display = "none";

    document.getElementById("captureState").textContent = "capturing";
    const hud = document.getElementById("captureHudState");
    if (hud) hud.textContent = "CAPTURING";

    addFeed("Captura conectada en modo preview único. Puedes ampliar la vista.", "info");

    if (captureTimer) clearInterval(captureTimer);
    if (captureDrawTimer) clearInterval(captureDrawTimer);

    captureTimer = setInterval(sampleCaptureFrame, 3000);
    captureDrawTimer = setInterval(drawCaptureFrame, 1000 / 30);

    const tracks = captureStream.getVideoTracks();
    if (tracks && tracks[0]) {
      tracks[0].onended = () => stopCapture();
    }
  } catch(e) {
    document.getElementById("captureState").textContent = "denied/offline";
    addFeed("Captura no iniciada: " + e.message, "warn");
    render();
  }
}

function stopCapture() {
  if (captureStream) captureStream.getTracks().forEach(t => t.stop());
  captureStream = null;

  if (captureTimer) clearInterval(captureTimer);
  if (captureDrawTimer) clearInterval(captureDrawTimer);
  captureTimer = null;
  captureDrawTimer = null;

  document.getElementById("captureState").textContent = "offline";
  const hud = document.getElementById("captureHudState");
  if (hud) hud.textContent = "OFFLINE";
}

function drawImageContain(ctx, video, canvas, mode) {
  const cw = canvas.width;
  const ch = canvas.height;
  const vw = video.videoWidth;
  const vh = video.videoHeight;
  if (!vw || !vh) return;

  const scale = mode === "fill" ? Math.max(cw / vw, ch / vh) : Math.min(cw / vw, ch / vh);
  const dw = vw * scale;
  const dh = vh * scale;
  const dx = (cw - dw) / 2;
  const dy = (ch - dh) / 2;

  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, cw, ch);
  ctx.drawImage(video, dx, dy, dw, dh);
}

function drawCaptureFrame() {
  const video = document.getElementById("captureVideo");
  if (!video || !video.videoWidth) return;

  const small = document.getElementById("captureCanvas");
  const smallCtx = small.getContext("2d");
  drawImageContain(smallCtx, video, small, captureFitMode);

  const big = document.getElementById("captureCanvasBig");
  if (big) {
    const bigCtx = big.getContext("2d");
    drawImageContain(bigCtx, video, big, captureFitMode);
  }

  captureFrameCounter++;
  const now = Date.now();
  if (now - captureLastFpsAt >= 1000) {
    captureFps = captureFrameCounter;
    captureFrameCounter = 0;
    captureLastFpsAt = now;
    const fps = document.getElementById("captureHudFps");
    if (fps) fps.textContent = "FPS " + captureFps;
  }

  const scan = document.getElementById("captureScanline");
  if (scan) scan.style.setProperty("--scanY", ((Date.now() / 35) % 100) + "%");

  const game = typeof selectedGame === "function" ? selectedGame() : null;
  const hudGame = document.getElementById("captureHudGame");
  if (hudGame && game) hudGame.textContent = game.name + " · " + game.country;
}

function sampleCaptureFrame() {
  if (!captureStream) return;
  addFeed("Frame live capturado en memoria. OCR/calibración pendiente.", "info");
  render();
}

function openCaptureModal() {
  const modal = document.getElementById("captureModal");
  if (!modal) return;
  modal.classList.add("open");
  document.body.style.overflow = "hidden";
}

function closeCaptureModal() {
  const modal = document.getElementById("captureModal");
  if (!modal) return;
  modal.classList.remove("open");
  document.body.style.overflow = "";
}

function toggleCaptureFit() {
  captureFitMode = captureFitMode === "fit" ? "fill" : "fit";
  const badge = document.getElementById("captureZoomState");
  if (badge) badge.textContent = captureFitMode.toUpperCase();
}
'@

if ($html -match 'async function startCapture\(\)') {
  $html = [regex]::Replace($html, $functionsRegex, $newFunctions, 1)
}

Set-Content -Encoding UTF8 $indexPath $html

Write-Host "Capture Pro v0.7 patch aplicado en $indexPath"
Write-Host "Siguiente: git add . ; git commit ; git push ; build workflow ; rollout restart"
