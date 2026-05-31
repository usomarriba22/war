
# CON War Room v1.0.1 — Network + WebSocket Debug Telemetry
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
Copy-Item "$extPath\content.js" "$extPath\content-before-v101-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item "$extPath\page-hook.js" "$extPath\page-hook-before-v101-$stamp.js" -Force -ErrorAction SilentlyContinue
Copy-Item $apiPath ".\02-apps\warroom-api\_legacy\main-before-v101-$stamp.py" -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# 1. content.js: forward all page-hook telemetry, plus heartbeat.
# -------------------------------------------------------------------
$contentJs = @'
const WARROOM_API = "http://127.0.0.1:8000";

function injectHook() {
  const s = document.createElement("script");
  s.src = chrome.runtime.getURL("page-hook.js");
  s.onload = () => s.remove();
  (document.documentElement || document.head || document.body).appendChild(s);
}

async function sendTelemetry(payload) {
  try {
    await fetch(`${WARROOM_API}/api/telemetry/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
  } catch (e) {
    // API local no disponible; silencioso para no molestar el juego.
  }
}

function visibleTextSnapshot() {
  const bodyText = (document.body && document.body.innerText) ? document.body.innerText : "";
  return bodyText.slice(0, 25000);
}

function collectDomTelemetry(reason = "interval") {
  sendTelemetry({
    source: "chrome-extension-dom",
    reason,
    url: location.href,
    title: document.title,
    ts: new Date().toISOString(),
    visible_text: visibleTextSnapshot(),
    meta: {
      ready_state: document.readyState,
      element_count: document.querySelectorAll("*").length
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
    network: msg.payload
  });
});

injectHook();

window.addEventListener("load", () => {
  setTimeout(() => collectDomTelemetry("load"), 1500);
});

setInterval(() => collectDomTelemetry("interval"), 5000);
'@
[System.IO.File]::WriteAllText("$extPath\content.js", $contentJs, $Utf8NoBom)

# -------------------------------------------------------------------
# 2. page-hook.js: capture fetch, XHR and WebSocket messages.
#    Read-only: does not modify requests/responses.
# -------------------------------------------------------------------
$pageHook = @'
(function () {
  if (window.__conWarRoomHookedV101) return;
  window.__conWarRoomHookedV101 = true;

  const MAX_BODY = 350000;
  const MAX_EVENTS_PER_MINUTE = 240;
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
        if (/token|auth|session|key|jwt|sid|password|pass|secret|credential/i.test(key)) {
          u.searchParams.set(key, "[redacted]");
        }
      }
      return u.toString();
    } catch {
      return String(url).slice(0, 500);
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
          ts: new Date().toISOString(),
          ...data
        }
      }, "*");
    } catch {}
  }

  function decodeMaybe(data, cb) {
    try {
      if (typeof data === "string") {
        cb(data);
        return;
      }

      if (data instanceof ArrayBuffer) {
        try {
          cb(new TextDecoder("utf-8").decode(data));
        } catch {
          post("websocket-binary", { body_type: "arraybuffer", byte_length: data.byteLength });
        }
        return;
      }

      if (data instanceof Blob) {
        data.text().then((txt) => cb(txt)).catch(() => {
          post("websocket-binary", { body_type: "blob", byte_length: data.size });
        });
        return;
      }

      cb(String(data));
    } catch {}
  }

  // Initial proof that page hook is running.
  post("hook-installed-v101", { message: "CON War Room v1.0.1 hook active" });

  // Fetch read-only hook.
  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async function (...args) {
      const response = await originalFetch.apply(this, args);

      try {
        const req = args[0];
        const reqUrl = safeUrl(req && (req.url || req));
        const clone = response.clone();
        const contentType = clone.headers.get("content-type") || "";

        // Capture metadata for every fetch.
        post("fetch-meta", {
          request_url: reqUrl,
          status: response.status,
          content_type: contentType
        });

        if (/json|text|plain|javascript|octet/i.test(contentType)) {
          clone.text().then((text) => {
            post("fetch-response", {
              request_url: reqUrl,
              status: response.status,
              content_type: contentType,
              body_length: text.length,
              body: bodyPreview(text)
            });
          }).catch(() => {});
        }
      } catch {}

      return response;
    };
  }

  // XHR read-only hook.
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

  // WebSocket read-only hook.
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
        post("websocket-error", {
          request_url: safe
        });
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

# -------------------------------------------------------------------
# 3. API main.py: preserve v1.0 behavior + add network debug endpoints
# -------------------------------------------------------------------
$api = [System.IO.File]::ReadAllText((Resolve-Path $apiPath))

# Ensure version/status text updated if current API is v1.0 script.
$api = $api.Replace('version="1.0.0"', 'version="1.0.1"')
$api = $api.Replace('"version": "1.0.0"', '"version": "1.0.1"')
$api = $api.Replace('"phase": "v1.0-auto-telemetry"', '"phase": "v1.0.1-network-websocket-debug"')
$api = $api.Replace('"telemetry-extension", "auto-ingest", "advisor", "movement", "multi-game"', '"telemetry-extension", "auto-ingest", "network-debug", "websocket-debug", "advisor", "movement", "multi-game"')

if ($api -notmatch 'def telemetry_debug') {
  $debugEndpoints = @'

@app.get("/api/telemetry/debug")
def telemetry_debug(limit: int = 30):
    limit = max(1, min(limit, 100))
    recent = TELEMETRY_EVENTS[-limit:]

    by_source = {}
    by_kind = {}
    network_events = []

    for event in recent:
        source = event.get("source") or "unknown"
        by_source[source] = by_source.get(source, 0) + 1

        network = event.get("network") or {}
        kind = network.get("kind") or event.get("reason") or "unknown"
        by_kind[kind] = by_kind.get(kind, 0) + 1

        if network:
            body = network.get("body") or ""
            network_events.append({
                "ts": event.get("received_at"),
                "kind": kind,
                "request_url": network.get("request_url"),
                "status": network.get("status"),
                "content_type": network.get("content_type"),
                "body_length": network.get("body_length") or len(body),
                "body_preview": body[:500] if isinstance(body, str) else ""
            })

    return {
        "total_stored": len(TELEMETRY_EVENTS),
        "recent_count": len(recent),
        "by_source": by_source,
        "by_kind": by_kind,
        "network_events": network_events[-limit:],
        "resources": LATEST_RESOURCES
    }

@app.get("/api/telemetry/network")
def telemetry_network(limit: int = 20):
    limit = max(1, min(limit, 100))
    items = []
    for event in TELEMETRY_EVENTS:
        network = event.get("network") or {}
        if not network:
            continue
        body = network.get("body") or ""
        items.append({
            "received_at": event.get("received_at"),
            "source": event.get("source"),
            "kind": network.get("kind"),
            "request_url": network.get("request_url"),
            "status": network.get("status"),
            "content_type": network.get("content_type"),
            "body_length": network.get("body_length") or (len(body) if isinstance(body, str) else 0),
            "body_preview": body[:1000] if isinstance(body, str) else ""
        })
    return {"network": items[-limit:]}
'@

  # Insert before advisor endpoints if possible, otherwise append.
  $insertPoint = '@app.post("/api/advisor/analyze")'
  if ($api.Contains($insertPoint)) {
    $api = $api.Replace($insertPoint, $debugEndpoints + "`n`n" + $insertPoint)
  } else {
    $api = $api + "`n" + $debugEndpoints
  }
}

[System.IO.File]::WriteAllText((Resolve-Path $apiPath), $api, $Utf8NoBom)

Write-Host "v1.0.1 Network + WebSocket Debug aplicado."
Write-Host "Siguiente:"
Write-Host "1) git add . ; git commit ; git push"
Write-Host "2) Build warroom-api"
Write-Host "3) Rollout restart warroom-api"
Write-Host "4) Recargar extension en chrome://extensions"
Write-Host "5) CTRL+F5 en Conflict of Nations"
Write-Host "6) Probar /api/telemetry/debug y /api/telemetry/network"
