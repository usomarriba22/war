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