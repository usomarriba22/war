
# CON War Room v1.0.3 — Stable Telemetry / No Flood / Sanitized URLs
# Ejecutar desde VS Code PowerShell:
# C:\Users\pmchl\Downloads\con-warroom-k8s-starter

Set-Location "$env:USERPROFILE\Downloads\con-warroom-k8s-starter"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$extPath = ".\05-extension\con-warroom-companion"
$apiPath = ".\02-apps\warroom-api\app\main.py"

if (!(Test-Path $extPath)) { throw "No existe la extension: $extPath" }
if (!(Test-Path $apiPath)) { throw "No existe API main.py: $apiPath" }

New-Item -ItemType Directory -Force -Path ".\02-apps\warroom-api\_legacy" | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item "$extPath\manifest.json" "$extPath\manifest-before-v103-$stamp.json" -Force -ErrorAction SilentlyContinue
Copy-Item "$extPath\content.js" "$extPath\content-before-v103-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item "$extPath\page-hook.js" "$extPath\page-hook-before-v103-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item $apiPath ".\02-apps\warroom-api\_legacy\main-before-v103-$stamp.py" -Force -ErrorAction SilentlyContinue

# 1) Manifest: limitar a dominios de CON/Bytro, no <all_urls>
$manifest = @'
{
  "manifest_version": 3,
  "name": "CON War Room Companion",
  "version": "1.0.3",
  "description": "Read-only telemetry collector for CON War Room. Stable mode: CON/Bytro frames only, sanitized URLs, no flood.",
  "permissions": ["storage"],
  "host_permissions": [
    "https://*.conflictnations.com/*",
    "https://conflictnations.com/*",
    "https://*.bytro.com/*",
    "https://*.doradogames.com/*",
    "http://127.0.0.1:8000/*",
    "http://localhost:8000/*"
  ],
  "content_scripts": [
    {
      "matches": [
        "https://*.conflictnations.com/*",
        "https://conflictnations.com/*",
        "https://*.bytro.com/*",
        "https://*.doradogames.com/*"
      ],
      "js": ["content.js"],
      "run_at": "document_start",
      "all_frames": true,
      "match_about_blank": true
    }
  ],
  "web_accessible_resources": [
    {
      "resources": ["page-hook.js"],
      "matches": [
        "https://*.conflictnations.com/*",
        "https://conflictnations.com/*",
        "https://*.bytro.com/*",
        "https://*.doradogames.com/*"
      ]
    }
  ],
  "action": {
    "default_title": "CON War Room",
    "default_popup": "popup.html"
  }
}
'@
[System.IO.File]::WriteAllText("$extPath\manifest.json", $manifest, $Utf8NoBom)

# 2) content.js: activar solo frames de juego, heartbeat bajo
$contentJs = @'
const WARROOM_API = "http://127.0.0.1:8000";

function isGameFrame() {
  const href = location.href || "";
  const ref = document.referrer || "";
  const joined = `${href} ${ref}`.toLowerCase();

  return (
    joined.includes("conflictnations.com") ||
    joined.includes("bytro.com") ||
    joined.includes("doradogames.com") ||
    joined.includes("con-client") ||
    joined.includes("congs") ||
    joined.includes("xgschat")
  );
}

async function sendTelemetry(payload) {
  try {
    await fetch(`${WARROOM_API}/api/telemetry/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
  } catch (e) {}
}

function injectHook() {
  try {
    const s = document.createElement("script");
    s.src = chrome.runtime.getURL("page-hook.js");
    s.onload = () => s.remove();
    (document.documentElement || document.head || document.body).appendChild(s);
  } catch (e) {
    sendTelemetry({
      source: "chrome-extension-frame",
      reason: "inject-error",
      url: location.href,
      title: document.title,
      ts: new Date().toISOString(),
      meta: { error: String(e), referrer: document.referrer || "" }
    });
  }
}

function sendFrameInventory(reason) {
  sendTelemetry({
    source: "chrome-extension-frame",
    reason,
    url: location.href,
    title: document.title,
    ts: new Date().toISOString(),
    visible_text: "",
    meta: {
      referrer: document.referrer || "",
      ready_state: document.readyState,
      top_frame: window.top === window,
      element_count: document.querySelectorAll ? document.querySelectorAll("*").length : 0
    }
  });
}

window.addEventListener("message", (event) => {
  if (event.source !== window) return;
  const msg = event.data;
  if (!msg || msg.__conWarRoom !== true) return;

  sendTelemetry({
    source: "chrome-extension-network",
    ts: new Date().toISOString(),
    url: location.href,
    title: document.title,
    network: {
      frame_url: location.href,
      frame_title: document.title,
      frame_referrer: document.referrer || "",
      ...msg.payload
    }
  });
});

if (isGameFrame()) {
  sendFrameInventory("content-script-start");
  injectHook();

  window.addEventListener("load", () => {
    setTimeout(() => sendFrameInventory("load"), 1000);
  });

  // heartbeat bajo: solo inventario, no DOM gigante
  setInterval(() => sendFrameInventory("heartbeat"), 30000);
}
'@
[System.IO.File]::WriteAllText("$extPath\content.js", $contentJs, $Utf8NoBom)

# 3) page-hook.js: sanitizar URL completa, no exponer query auth, rate limit estricto
$pageHook = @'
(function () {
  if (window.__conWarRoomHookedV103) return;
  window.__conWarRoomHookedV103 = true;

  const MAX_BODY = 120000;
  const MAX_EVENTS_PER_MINUTE = 80;
  let eventCounter = 0;
  setInterval(() => { eventCounter = 0; }, 60000);

  function canSend() {
    eventCounter += 1;
    return eventCounter <= MAX_EVENTS_PER_MINUTE;
  }

  function sanitizedUrl(url) {
    try {
      const u = new URL(String(url), location.href);
      const keep = ["gameID", "uid", "source", "L", "gs", "mapID", "modID", "titleID", "lang"];
      for (const key of Array.from(u.searchParams.keys())) {
        if (!keep.includes(key)) u.searchParams.set(key, "[redacted]");
      }
      return u.origin + u.pathname + (u.search ? u.search : "");
    } catch {
      return String(url).slice(0, 300);
    }
  }

  function shortFrameUrl() {
    try {
      const u = new URL(location.href);
      const keep = ["gameID", "uid", "source", "L", "gs", "mapID", "modID", "titleID", "lang"];
      for (const key of Array.from(u.searchParams.keys())) {
        if (!keep.includes(key)) u.searchParams.set(key, "[redacted]");
      }
      return u.origin + u.pathname + u.search;
    } catch {
      return location.href.slice(0, 300);
    }
  }

  function post(kind, data) {
    if (!canSend()) return;
    try {
      window.postMessage({
        __conWarRoom: true,
        payload: {
          kind,
          page_url: shortFrameUrl(),
          page_title: document.title,
          page_referrer: document.referrer ? sanitizedUrl(document.referrer) : "",
          ts: new Date().toISOString(),
          ...data
        }
      }, "*");
    } catch {}
  }

  function looksLikeGameState(text, url) {
    const t = (text || "").slice(0, 4000);
    const u = String(url || "").toLowerCase();
    return (
      u.includes("congs") ||
      t.includes("UltAutoGameState") ||
      t.includes("UltMapState") ||
      t.includes("UltArmyState") ||
      t.includes("UltResource") ||
      t.includes("dayOfGame") ||
      t.includes("stateType")
    );
  }

  function preview(text) {
    return String(text || "").slice(0, MAX_BODY);
  }

  post("hook-installed-v103", { message: "CON War Room v1.0.3 hook active" });

  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async function (...args) {
      const response = await originalFetch.apply(this, args);
      try {
        const req = args[0];
        const reqUrl = sanitizedUrl(req && (req.url || req));
        const clone = response.clone();
        const contentType = clone.headers.get("content-type") || "";

        if (/congs|bytro|conflictnations/i.test(reqUrl)) {
          post("fetch-meta", { request_url: reqUrl, status: response.status, content_type: contentType });
        }

        clone.text().then((text) => {
          if (looksLikeGameState(text, reqUrl)) {
            post("fetch-response", {
              request_url: reqUrl,
              status: response.status,
              content_type: contentType,
              body_length: text.length,
              body: preview(text)
            });
          }
        }).catch(() => {});
      } catch {}
      return response;
    };
  }

  const OriginalXHR = window.XMLHttpRequest;
  if (OriginalXHR) {
    const originalOpen = OriginalXHR.prototype.open;
    const originalSend = OriginalXHR.prototype.send;

    OriginalXHR.prototype.open = function (method, url, ...rest) {
      this.__conWarRoomUrl = sanitizedUrl(url);
      this.__conWarRoomMethod = method;
      return originalOpen.call(this, method, url, ...rest);
    };

    OriginalXHR.prototype.send = function (...args) {
      this.addEventListener("load", function () {
        try {
          const contentType = this.getResponseHeader("content-type") || "";
          const text = typeof this.responseText === "string" ? this.responseText : "";

          if (/congs|bytro|conflictnations/i.test(this.__conWarRoomUrl)) {
            post("xhr-meta", {
              request_url: this.__conWarRoomUrl,
              method: this.__conWarRoomMethod,
              status: this.status,
              content_type: contentType,
              body_length: text.length
            });
          }

          if (looksLikeGameState(text, this.__conWarRoomUrl)) {
            post("xhr-response", {
              request_url: this.__conWarRoomUrl,
              method: this.__conWarRoomMethod,
              status: this.status,
              content_type: contentType,
              body_length: text.length,
              body: preview(text)
            });
          }
        } catch {}
      });
      return originalSend.apply(this, args);
    };
  }

  const OriginalWebSocket = window.WebSocket;
  if (OriginalWebSocket) {
    const WrappedWebSocket = function (url, protocols) {
      const ws = protocols !== undefined ? new OriginalWebSocket(url, protocols) : new OriginalWebSocket(url);
      const safe = sanitizedUrl(url);

      post("websocket-open", { request_url: safe });

      ws.addEventListener("message", function (event) {
        try {
          if (typeof event.data === "string" && looksLikeGameState(event.data, safe)) {
            post("websocket-message", {
              request_url: safe,
              body_length: event.data.length,
              body: preview(event.data)
            });
          }
        } catch {}
      });

      return ws;
    };
    WrappedWebSocket.prototype = OriginalWebSocket.prototype;
    Object.defineProperty(WrappedWebSocket, "CONNECTING", { value: OriginalWebSocket.CONNECTING });
    Object.defineProperty(WrappedWebSocket, "OPEN", { value: OriginalWebSocket.OPEN });
    Object.defineProperty(WrappedWebSocket, "CLOSING", { value: OriginalWebSocket.CLOSING });
    Object.defineProperty(WrappedWebSocket, "CLOSED", { value: OriginalWebSocket.CLOSED });
    window.WebSocket = WrappedWebSocket;
  }
})();
'@
[System.IO.File]::WriteAllText("$extPath\page-hook.js", $pageHook, $Utf8NoBom)

# 4) API: versión, endpoints ligeros, limitar payload retornado
$api = [System.IO.File]::ReadAllText((Resolve-Path $apiPath))
$api = $api.Replace('version="1.0.0"', 'version="1.0.3"')
$api = $api.Replace('version="1.0.1"', 'version="1.0.3"')
$api = $api.Replace('version="1.0.2"', 'version="1.0.3"')
$api = $api.Replace('"version": "1.0.0"', '"version": "1.0.3"')
$api = $api.Replace('"version": "1.0.1"', '"version": "1.0.3"')
$api = $api.Replace('"version": "1.0.2"', '"version": "1.0.3"')
$api = $api.Replace('"phase": "v1.0-auto-telemetry"', '"phase": "v1.0.3-stable-telemetry"')
$api = $api.Replace('"phase": "v1.0.1-network-websocket-debug"', '"phase": "v1.0.3-stable-telemetry"')
$api = $api.Replace('"phase": "v1.0.2-allframes-game-network"', '"phase": "v1.0.3-stable-telemetry"')

if ($api -notmatch 'def telemetry_game_network_light') {
  $extra = @'

@app.get("/api/telemetry/game-network-light")
def telemetry_game_network_light(limit: int = 10):
    limit = max(1, min(limit, 30))
    items = []

    for event in TELEMETRY_EVENTS:
        network = event.get("network") or {}
        if not network:
            continue
        body = network.get("body") or ""
        if is_noise_event(event):
            continue
        items.append({
            "received_at": event.get("received_at"),
            "kind": network.get("kind"),
            "domain": event_domain(event),
            "request_url": network.get("request_url"),
            "status": network.get("status"),
            "content_type": network.get("content_type"),
            "body_length": network.get("body_length") or (len(body) if isinstance(body, str) else 0),
            "body_preview": body[:300] if isinstance(body, str) else ""
        })

    return {"network": items[-limit:], "resources": LATEST_RESOURCES}

@app.get("/api/telemetry/latest-resource-state")
def telemetry_latest_resource_state():
    return {
        "resources": LATEST_RESOURCES,
        "event_count": len(TELEMETRY_EVENTS),
        "time": datetime.now(timezone.utc).isoformat()
    }
'@
  $insertPoint = '@app.post("/api/advisor/analyze")'
  if ($api.Contains($insertPoint)) {
    $api = $api.Replace($insertPoint, $extra + "`n`n" + $insertPoint)
  } else {
    $api += "`n" + $extra
  }
}

[System.IO.File]::WriteAllText((Resolve-Path $apiPath), $api, $Utf8NoBom)

Write-Host "v1.0.3 Stable Telemetry aplicado."
Write-Host "Ahora:"
Write-Host "1) git add . ; git commit -m 'Stabilize telemetry capture' ; git push"
Write-Host "2) Build warroom-api + rollout restart"
Write-Host "3) Recargar extension"
Write-Host "4) Probar SOLO una partida abierta"
Write-Host "5) Usar /api/telemetry/game-network-light y /api/telemetry/latest-resource-state"
