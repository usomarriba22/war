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