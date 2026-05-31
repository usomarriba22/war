(function () {
  if (window.__conWarRoomHooked) return;
  window.__conWarRoomHooked = true;

  function safeUrl(url) {
    try {
      const u = new URL(String(url), location.href);
      for (const key of Array.from(u.searchParams.keys())) {
        if (/token|auth|session|key|jwt|sid|password|pass/i.test(key)) u.searchParams.set(key, "[redacted]");
      }
      return u.toString();
    } catch { return String(url).slice(0, 500); }
  }

  function looksUseful(text) {
    if (!text || text.length < 20) return false;
    const t = text.toLowerCase();
    return ["resource","supplies","components","fuel","electronics","rare","manpower","money","province","city","unit","army","coalition","research","victory"].some(x => t.includes(x));
  }

  function post(kind, data) {
    try {
      window.postMessage({ __conWarRoom: true, payload: { kind, page_url: location.href, ts: new Date().toISOString(), ...data } }, "*");
    } catch {}
  }

  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async function (...args) {
      const response = await originalFetch.apply(this, args);
      try {
        const reqUrl = safeUrl(args[0] && (args[0].url || args[0]));
        const clone = response.clone();
        const contentType = clone.headers.get("content-type") || "";
        if (/json|text|plain/i.test(contentType)) {
          clone.text().then((text) => {
            if (looksUseful(text)) {
              post("fetch-response", { request_url: reqUrl, status: response.status, content_type: contentType, body: text.slice(0, 250000) });
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
          if (/json|text|plain/i.test(contentType) && looksUseful(text)) {
            post("xhr-response", { request_url: this.__conWarRoomUrl, method: this.__conWarRoomMethod, status: this.status, content_type: contentType, body: text.slice(0, 250000) });
          }
        } catch {}
      });
      return originalSend.apply(this, args);
    };
  }

  post("hook-installed", { message: "CON War Room hook active" });
})();