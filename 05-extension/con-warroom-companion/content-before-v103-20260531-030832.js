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