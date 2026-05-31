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