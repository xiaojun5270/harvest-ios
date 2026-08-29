(() => {
  const api = globalThis.browser || globalThis.chrome;

  const compatibleCookieDetails = (details = {}) => {
    const compatible = { ...details };
    delete compatible.partitionKey;
    return compatible;
  };

  if (api?.cookies && typeof api.cookies.getAll === "function") {
    const originalCookies = api.cookies;
    const originalGetAll = originalCookies.getAll.bind(originalCookies);
    let installed = false;
    try {
      const compatibleGetAll = (details, ...rest) => originalGetAll(compatibleCookieDetails(details), ...rest);
      originalCookies.getAll = compatibleGetAll;
      installed = originalCookies.getAll === compatibleGetAll;
    } catch (_) {
      // A read-only Safari API object is handled by the proxy below.
    }

    if (!installed) {
      const compatibleCookies = new Proxy({}, {
        get(_, property) {
          if (property === "getAll") {
            return (details, ...rest) => originalGetAll(compatibleCookieDetails(details), ...rest);
          }
          const value = originalCookies[property];
          return typeof value === "function" ? value.bind(originalCookies) : value;
        }
      });
      const compatibleAPI = new Proxy({}, {
        get(_, property) {
          if (property === "cookies") return compatibleCookies;
          const value = api[property];
          return typeof value === "function" ? value.bind(api) : value;
        }
      });
      for (const namespace of ["browser", "chrome"]) {
        if (globalThis[namespace] && globalThis[namespace] !== api) continue;
        try {
          Object.defineProperty(globalThis, namespace, {
            configurable: true,
            value: compatibleAPI
          });
        } catch (_) {
          // Keep the original namespace if Safari locks the global property.
        }
      }
    }
  }

  let dismissTimer;
  const feedbackTone = (message) => {
    const value = message.toLowerCase();
    if (/(失败|错误|无效|invalid|fail|error|无法|不允许)/i.test(value)) return "error";
    if (/(成功|完成|已保存|saved|success|done)/i.test(value)) return "success";
    return "info";
  };
  const palette = {
    success: { background: "#ecfdf5", border: "#10b981", text: "#065f46", icon: "✓" },
    error: { background: "#fff1f2", border: "#f43f5e", text: "#9f1239", icon: "!" },
    info: { background: "#eff6ff", border: "#3b82f6", text: "#1e40af", icon: "i" }
  };

  const showFeedback = (rawMessage) => {
    const message = String(rawMessage ?? "操作已完成").trim() || "操作已完成";
    const tone = feedbackTone(message);
    const colors = palette[tone];
    let banner = document.getElementById("cookiecloud-safari-feedback");
    if (!banner) {
      banner = document.createElement("div");
      banner.id = "cookiecloud-safari-feedback";
      banner.setAttribute("role", "status");
      banner.setAttribute("aria-live", "polite");
      Object.assign(banner.style, {
        position: "fixed",
        top: "10px",
        left: "12px",
        right: "12px",
        zIndex: "2147483647",
        display: "grid",
        gridTemplateColumns: "24px 1fr 24px",
        alignItems: "center",
        gap: "8px",
        padding: "10px 12px",
        border: "1px solid",
        borderRadius: "10px",
        boxShadow: "0 10px 28px rgba(15, 23, 42, 0.18)",
        font: "600 13px/1.45 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
      });
      const icon = document.createElement("strong");
      icon.dataset.role = "icon";
      icon.style.textAlign = "center";
      const text = document.createElement("span");
      text.dataset.role = "message";
      text.style.wordBreak = "break-word";
      const close = document.createElement("button");
      close.type = "button";
      close.textContent = "×";
      close.setAttribute("aria-label", "关闭提示");
      Object.assign(close.style, {
        appearance: "none",
        border: "0",
        background: "transparent",
        color: "inherit",
        cursor: "pointer",
        padding: "0",
        font: "700 20px/1 sans-serif"
      });
      close.addEventListener("click", () => banner.remove());
      banner.append(icon, text, close);
      (document.body || document.documentElement).appendChild(banner);
    }
    banner.querySelector('[data-role="icon"]').textContent = colors.icon;
    banner.querySelector('[data-role="message"]').textContent = message;
    Object.assign(banner.style, {
      display: "grid",
      background: colors.background,
      borderColor: colors.border,
      color: colors.text
    });
    clearTimeout(dismissTimer);
    dismissTimer = setTimeout(() => banner.remove(), tone === "error" ? 8000 : 5000);
  };

  document.addEventListener("click", (event) => {
    const button = event.target?.closest?.("button");
    if (!button || button.closest("#cookiecloud-safari-feedback")) return;
    const label = String(button.textContent || "").replace(/\s+/g, " ").trim();
    if (/(手动同步|manual sync)/i.test(label)) {
      showFeedback("正在手动同步，请稍候…");
    } else if (/(^|\s)(测试|test)(\s|$)/i.test(label)) {
      showFeedback("正在测试服务器连接…");
    } else if (/(^|\s)(保存|save)(\s|$)/i.test(label)) {
      showFeedback("正在保存设置…");
    }
  }, true);

  globalThis.alert = showFeedback;
  globalThis.__cookieCloudShowFeedback = showFeedback;
  globalThis.addEventListener("unhandledrejection", (event) => {
    const detail = event.reason?.message || event.reason || "未知错误";
    showFeedback(`操作失败：${detail}`);
  });
  globalThis.addEventListener("error", (event) => {
    if (event.message) showFeedback(`操作失败：${event.message}`);
  });
})();
