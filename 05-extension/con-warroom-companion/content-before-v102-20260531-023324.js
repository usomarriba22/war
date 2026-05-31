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