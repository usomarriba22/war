
# CON War Room v1.0.2 — All Frames + Game Network Discovery
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
Copy-Item "$extPath\manifest.json" "$extPath\manifest-before-v102-$stamp.json" -Force -ErrorAction SilentlyContinue
Copy-Item "$extPath\content.js" "$extPath\content-before-v102-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item "$extPath\page-hook.js" "$extPath\page-hook-before-v102-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item $apiPath ".\02-apps\warroom-api\_legacy\main-before-v102-$stamp.py" -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# 1. Manifest: all frames. This is temporary for discovery.
# -----------------------------------------------------------------------------
$manifest = @'
{
  "manifest_version": 3,
  "name": "CON War Room Companion",
  "version": "1.0.2",
  "description": "Read-only telemetry collector for CON War Room. Discovery mode: all frames, no clicks, no movements.",
  "permissions": ["storage"],
  "host_permissions": ["<all_urls>"],
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_start",
      "all_frames": true,
      "match_about_blank": true
    }
  ],
  "web_accessible_resources": [
    {
      "resources": ["page-hook.js"],
      "matches": ["<all_urls>"]
    }
  ],
  "action": {
    "default_title": "CON War Room",
    "default_popup": "popup.html"
  }
}
'@
[System.IO.File]::WriteAllText("$extPath\manifest.json", $manifest, $Utf8NoBom)

# -----------------------------------------------------------------------------
# 2. content.js: inject in relevant frames and send frame inventory.
# -----------------------------------------------------------------------------
$contentJs = @'
const WARROOM_API = "http://127.0.0.1:8000";

function gameContextScore() {
  const href = location.href || "";
  const ref = document.referrer || "";
  const title = document.title || "";
  const joined = `${href} ${ref} ${title}`.toLowerCase();

  let score = 0;
  if (joined.includes("conflictnations")) score += 100;
  if (joined.includes("doradogames")) score += 50;
  if (joined.includes("bytro")) score += 50;
  if (joined.includes("supremacy")) score += 30;
  if (joined.includes("callofwar")) score += 30;
  if (joined.includes("game")) score += 5;
  if (joined.includes("client")) score += 5;
  return score;
}

function shouldActivate() {
  // Discovery mode: activate on CON page and child frames referenced by CON.
  return gameContextScore() > 0;
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

function frameMeta(reason) {
  let topSame = false;
  try { topSame = window.top === window; } catch {}
  return {
    source: "chrome-extension-frame",
    reason,
    url: location.href,
    title: document.title,
    ts: new Date().toISOString(),
    visible_text: "",
    meta: {
      referrer: document.referrer || "",
      ready_state: document.readyState,
      element_count: document.querySelectorAll ? document.querySelectorAll("*").length : 0,
      top_frame: topSame,
      game_context_score: gameContextScore()
    }
  };
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

function collectDomTelemetry(reason = "interval") {
  let text = "";
  try {
    text = (document.body && document.body.innerText) ? document.body.innerText.slice(0, 25000) : "";
  } catch {}

  sendTelemetry({
    source: "chrome-extension-dom",
    reason,
    url: location.href,
    title: document.title,
    ts: new Date().toISOString(),
    visible_text: text,
    meta: {
      referrer: document.referrer || "",
      ready_state: document.readyState,
      element_count: document.querySelectorAll ? document.querySelectorAll("*").length : 0,
      game_context_score: gameContextScore()
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

// Always send frame inventory for likely CON-related frames.
if (shouldActivate()) {
  sendTelemetry(frameMeta("content-script-start"));
  injectHook();

  window.addEventListener("load", () => {
    setTimeout(() => {
      sendTelemetry(frameMeta("load"));
      collectDomTelemetry("load");
    }, 1000);
  });

  setInterval(() => collectDomTelemetry("interval"), 8000);
}
'@
[System.IO.File]::WriteAllText("$extPath\content.js", $contentJs, $Utf8NoBom)

# -----------------------------------------------------------------------------
# 3. page-hook.js: fetch/xhr/websocket in every relevant frame.
# -----------------------------------------------------------------------------
$pageHook = @'
(function () {
  if (window.__conWarRoomHookedV102) return;
  window.__conWarRoomHookedV102 = true;

  const MAX_BODY = 500000;
  const MAX_EVENTS_PER_MINUTE = 500;
  let eventCounter = 0;
  setInterval(() => { eventCounter = 0; }, 60000);

  function canSend() {
    eventCounter += 1;
    return eventCounter <= MAX_EVENTS_PER_MINUTE;
  }

  function safeUrl(url) {
    try {
      const u = new URL(String(url), location.href);
      for (const key of Array.from(u.searchParams.keys())) {
        if (/token|auth|session|key|jwt|sid|password|pass|secret|credential|access/i.test(key)) {
          u.searchParams.set(key, "[redacted]");
        }
      }
      return u.toString();
    } catch {
      return String(url).slice(0, 800);
    }
  }

  function bodyPreview(text) {
    if (text == null) return "";
    return String(text).slice(0, MAX_BODY);
  }

  function post(kind, data) {
    if (!canSend()) return;
    try {
      window.postMessage({
        __conWarRoom: true,
        payload: {
          kind,
          page_url: location.href,
          page_title: document.title,
          page_referrer: document.referrer || "",
          ts: new Date().toISOString(),
          ...data
        }
      }, "*");
    } catch {}
  }

  function decodeMaybe(data, cb) {
    try {
      if (typeof data === "string") return cb(data);

      if (data instanceof ArrayBuffer) {
        try { return cb(new TextDecoder("utf-8").decode(data)); }
        catch { return post("websocket-binary", { body_type: "arraybuffer", byte_length: data.byteLength }); }
      }

      if (data instanceof Blob) {
        return data.text().then((txt) => cb(txt)).catch(() => {
          post("websocket-binary", { body_type: "blob", byte_length: data.size });
        });
      }

      cb(String(data));
    } catch {}
  }

  post("hook-installed-v102", { message: "CON War Room v1.0.2 hook active" });

  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async function (...args) {
      const response = await originalFetch.apply(this, args);
      try {
        const req = args[0];
        const reqUrl = safeUrl(req && (req.url || req));
        const clone = response.clone();
        const contentType = clone.headers.get("content-type") || "";

        post("fetch-meta", {
          request_url: reqUrl,
          status: response.status,
          content_type: contentType
        });

        if (/json|text|plain|javascript|octet|protobuf|binary/i.test(contentType) || response.status === 200) {
          clone.text().then((text) => {
            if (text && text.length > 0) {
              post("fetch-response", {
                request_url: reqUrl,
                status: response.status,
                content_type: contentType,
                body_length: text.length,
                body: bodyPreview(text)
              });
            }
          }).catch(() => {});
        }
      } catch {}
      return response;
    };
  }

  const OriginalXHR = window.XMLHttpRequest;
  if (OriginalXHR) {
    const originalOpen = OriginalXHR.prototype.open;
    const originalSend = OriginalXHR.prototype.send;

    OriginalXHR.prototype.open = function (method, url, ...rest) {
      this.__conWarRoomUrl = safeUrl(url);
      this.__conWarRoomMethod = method;
      return originalOpen.call(this, method, url, ...rest);
    };

    OriginalXHR.prototype.send = function (...args) {
      this.addEventListener("load", function () {
        try {
          const contentType = this.getResponseHeader("content-type") || "";
          const text = typeof this.responseText === "string" ? this.responseText : "";

          post("xhr-meta", {
            request_url: this.__conWarRoomUrl,
            method: this.__conWarRoomMethod,
            status: this.status,
            content_type: contentType,
            body_length: text.length
          });

          if (text) {
            post("xhr-response", {
              request_url: this.__conWarRoomUrl,
              method: this.__conWarRoomMethod,
              status: this.status,
              content_type: contentType,
              body_length: text.length,
              body: bodyPreview(text)
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
      const safe = safeUrl(url);

      post("websocket-open", {
        request_url: safe,
        protocol_count: Array.isArray(protocols) ? protocols.length : (protocols ? 1 : 0)
      });

      ws.addEventListener("message", function (event) {
        decodeMaybe(event.data, function (txt) {
          post("websocket-message", {
            request_url: safe,
            body_length: txt.length,
            body: bodyPreview(txt)
          });
        });
      });

      ws.addEventListener("close", function (event) {
        post("websocket-close", {
          request_url: safe,
          code: event.code,
          reason: event.reason || ""
        });
      });

      ws.addEventListener("error", function () {
        post("websocket-error", { request_url: safe });
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

# -----------------------------------------------------------------------------
# 4. API: add clearer debug endpoints, keep existing behavior.
# -----------------------------------------------------------------------------
$api = [System.IO.File]::ReadAllText((Resolve-Path $apiPath))
$api = $api.Replace('version="1.0.0"', 'version="1.0.2"')
$api = $api.Replace('version="1.0.1"', 'version="1.0.2"')
$api = $api.Replace('"version": "1.0.0"', '"version": "1.0.2"')
$api = $api.Replace('"version": "1.0.1"', '"version": "1.0.2"')
$api = $api.Replace('"phase": "v1.0-auto-telemetry"', '"phase": "v1.0.2-allframes-game-network"')
$api = $api.Replace('"phase": "v1.0.1-network-websocket-debug"', '"phase": "v1.0.2-allframes-game-network"')

if ($api -notmatch 'NOISE_DOMAINS') {
  $api = $api.Replace('import re', 'import re' + "`n" + 'from urllib.parse import urlparse')
  $api = $api.Replace('LATEST_RESOURCES: Dict[str, dict] = {}', @'
LATEST_RESOURCES: Dict[str, dict] = {}

NOISE_DOMAINS = [
    "google-analytics.com",
    "region1.google-analytics.com",
    "www.google-analytics.com",
    "www.google.com",
    "google.com",
    "googletagmanager.com",
    "pixel-config.reddit.com",
    "reddit.com",
    "s.yimg.com",
    "yimg.com",
    "doubleclick.net",
    "facebook.com",
    "bing.com"
]

def event_domain(event: dict) -> str:
    network = event.get("network") or {}
    url = network.get("request_url") or network.get("frame_url") or event.get("url") or ""
    try:
        return urlparse(url).netloc.lower()
    except Exception:
        return ""

def is_noise_event(event: dict) -> bool:
    domain = event_domain(event)
    return any(noise in domain for noise in NOISE_DOMAINS)
'@)
}

if ($api -notmatch 'def telemetry_clear') {
  $extraEndpoints = @'

@app.post("/api/telemetry/clear")
def telemetry_clear():
    TELEMETRY_EVENTS.clear()
    LATEST_RESOURCES.clear()
    return {"status": "cleared", "time": datetime.now(timezone.utc).isoformat()}

@app.get("/api/telemetry/domains")
def telemetry_domains(limit: int = 300):
    limit = max(1, min(limit, 1000))
    recent = TELEMETRY_EVENTS[-limit:]
    domains = {}
    kinds = {}

    for event in recent:
        domain = event_domain(event) or "unknown"
        domains[domain] = domains.get(domain, 0) + 1

        network = event.get("network") or {}
        kind = network.get("kind") or event.get("reason") or "unknown"
        kinds[kind] = kinds.get(kind, 0) + 1

    return {
        "total_stored": len(TELEMETRY_EVENTS),
        "checked": len(recent),
        "domains": dict(sorted(domains.items(), key=lambda x: x[1], reverse=True)),
        "kinds": dict(sorted(kinds.items(), key=lambda x: x[1], reverse=True))
    }

@app.get("/api/telemetry/game-network")
def telemetry_game_network(limit: int = 50):
    limit = max(1, min(limit, 200))
    items = []

    for event in TELEMETRY_EVENTS:
        network = event.get("network") or {}
        if not network:
            continue
        if is_noise_event(event):
            continue

        body = network.get("body") or ""
        items.append({
            "received_at": event.get("received_at"),
            "source": event.get("source"),
            "kind": network.get("kind"),
            "domain": event_domain(event),
            "request_url": network.get("request_url"),
            "frame_url": network.get("frame_url"),
            "frame_referrer": network.get("frame_referrer"),
            "status": network.get("status"),
            "content_type": network.get("content_type"),
            "body_length": network.get("body_length") or (len(body) if isinstance(body, str) else 0),
            "body_preview": body[:1500] if isinstance(body, str) else ""
        })

    return {"network": items[-limit:], "resources": LATEST_RESOURCES}

@app.get("/api/telemetry/frames")
def telemetry_frames(limit: int = 100):
    limit = max(1, min(limit, 300))
    frames = []

    for event in TELEMETRY_EVENTS:
        if event.get("source") != "chrome-extension-frame":
            continue
        meta = event.get("meta") or {}
        frames.append({
            "received_at": event.get("received_at"),
            "reason": event.get("reason"),
            "url": event.get("url"),
            "title": event.get("title"),
            "referrer": meta.get("referrer"),
            "top_frame": meta.get("top_frame"),
            "game_context_score": meta.get("game_context_score"),
            "element_count": meta.get("element_count")
        })

    return {"frames": frames[-limit:]}
'@

  $insertPoint = '@app.post("/api/advisor/analyze")'
  if ($api.Contains($insertPoint)) {
    $api = $api.Replace($insertPoint, $extraEndpoints + "`n`n" + $insertPoint)
  } else {
    $api = $api + "`n" + $extraEndpoints
  }
}

[System.IO.File]::WriteAllText((Resolve-Path $apiPath), $api, $Utf8NoBom)

Write-Host "v1.0.2 All Frames + Game Network Discovery aplicado."
Write-Host "IMPORTANTE:"
Write-Host "- Recargar extension en chrome://extensions."
Write-Host "- Cerrar TODAS las pestanas de Conflict of Nations."
Write-Host "- Abrir de nuevo la partida desde cero, no solo F5."
Write-Host "- Probar endpoints: /api/telemetry/frames, /api/telemetry/domains, /api/telemetry/game-network"
