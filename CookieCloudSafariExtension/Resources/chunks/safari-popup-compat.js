(() => {
  const api = globalThis.browser || globalThis.chrome;

  const syncStats = {
    operation: "",
    active: false,
    read: 0,
    readErrors: 0,
    writeSuccess: 0,
    writeFailure: 0,
    uploadSuccess: 0,
    uploadFailure: 0
  };
  let logPanel;
  let logBody;
  let logSummary;

  const countSummary = () => {
    if (syncStats.writeSuccess + syncStats.writeFailure > 0) {
      return `写入成功 ${syncStats.writeSuccess} · 失败 ${syncStats.writeFailure}`;
    }
    if (syncStats.uploadSuccess + syncStats.uploadFailure > 0) {
      return `上传成功 ${syncStats.uploadSuccess} · 失败 ${syncStats.uploadFailure}`;
    }
    if (syncStats.readErrors > 0) return `Cookie 读取失败 ${syncStats.readErrors} 次`;
    return `已读取 ${syncStats.read} 条 Cookie`;
  };

  const ensureLogPanel = () => {
    if (logPanel?.isConnected) {
      logPanel.style.display = "block";
      return;
    }
    logPanel = document.createElement("section");
    logPanel.id = "cookiecloud-safari-log";
    logPanel.setAttribute("aria-label", "CookieCloud 同步日志");
    Object.assign(logPanel.style, {
      position: "fixed",
      right: "12px",
      bottom: "10px",
      left: "12px",
      zIndex: "2147483646",
      overflow: "hidden",
      color: "#e2e8f0",
      background: "rgba(15, 23, 42, 0.96)",
      border: "1px solid rgba(148, 163, 184, 0.35)",
      borderRadius: "10px",
      boxShadow: "0 12px 30px rgba(15, 23, 42, 0.30)",
      font: "500 11px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace"
    });
    const header = document.createElement("header");
    Object.assign(header.style, {
      display: "flex",
      alignItems: "center",
      gap: "8px",
      minHeight: "34px",
      padding: "6px 9px",
      background: "rgba(30, 41, 59, 0.98)"
    });
    const title = document.createElement("strong");
    title.textContent = "同步日志";
    title.style.whiteSpace = "nowrap";
    logSummary = document.createElement("span");
    logSummary.style.cssText = "margin-left:auto;color:#86efac;text-align:right";
    const close = document.createElement("button");
    close.type = "button";
    close.textContent = "×";
    close.setAttribute("aria-label", "关闭同步日志");
    Object.assign(close.style, {
      appearance: "none",
      border: "0",
      padding: "0 2px",
      color: "#cbd5e1",
      background: "transparent",
      cursor: "pointer",
      font: "700 18px/1 sans-serif"
    });
    close.addEventListener("click", () => { logPanel.style.display = "none"; });
    header.append(title, logSummary, close);
    logBody = document.createElement("div");
    Object.assign(logBody.style, {
      maxHeight: "126px",
      padding: "7px 9px",
      overflowY: "auto",
      overscrollBehavior: "contain"
    });
    logPanel.append(header, logBody);
    (document.body || document.documentElement).appendChild(logPanel);
  };

  const updateLogSummary = () => {
    if (!logSummary) return;
    logSummary.textContent = countSummary();
    logSummary.style.color = syncStats.writeFailure + syncStats.uploadFailure + syncStats.readErrors > 0
      ? "#fda4af"
      : "#86efac";
  };

  const safeErrorText = (error) => String(error?.message || error || "未知错误").slice(0, 180);

  const appendLog = (message, tone = "info") => {
    ensureLogPanel();
    const row = document.createElement("div");
    const timestamp = new Date().toLocaleTimeString([], { hour12: false });
    row.textContent = `[${timestamp}] ${message}`;
    row.style.color = tone === "error" ? "#fda4af" : tone === "success" ? "#86efac" : "#cbd5e1";
    logBody.appendChild(row);
    while (logBody.childElementCount > 60) logBody.firstElementChild?.remove();
    logBody.scrollTop = logBody.scrollHeight;
    updateLogSummary();
    const method = tone === "error" ? "error" : tone === "success" ? "info" : "log";
    console[method](`[CookieCloud Safari] ${message}`);
  };

  const beginOperation = (operation) => {
    Object.assign(syncStats, {
      operation,
      active: true,
      read: 0,
      readErrors: 0,
      writeSuccess: 0,
      writeFailure: 0,
      uploadSuccess: 0,
      uploadFailure: 0
    });
    ensureLogPanel();
    logBody.replaceChildren();
    appendLog(`${operation}开始`);
  };

  const compatibleCookieDetails = (details = {}) => {
    const compatible = { ...details };
    delete compatible.partitionKey;
    return compatible;
  };

  if (api?.cookies && typeof api.cookies.getAll === "function") {
    const originalCookies = api.cookies;
    const originalGetAll = originalCookies.getAll.bind(originalCookies);
    const originalSet = typeof originalCookies.set === "function" ? originalCookies.set.bind(originalCookies) : null;
    const compatibleGetAll = async (details, ...rest) => {
      try {
        const cookies = await originalGetAll(compatibleCookieDetails(details), ...rest);
        syncStats.read = Array.isArray(cookies) ? cookies.length : 0;
        appendLog(`已读取 ${syncStats.read} 条 Cookie`, "success");
        return cookies;
      } catch (error) {
        syncStats.readErrors += 1;
        appendLog(`Cookie 读取失败：${safeErrorText(error)}`, "error");
        throw error;
      }
    };
    const compatibleSet = originalSet ? async (details, ...rest) => {
      try {
        const cookie = await originalSet(details, ...rest);
        syncStats.writeSuccess += 1;
        updateLogSummary();
        return cookie;
      } catch (error) {
        syncStats.writeFailure += 1;
        appendLog(`第 ${syncStats.writeSuccess + syncStats.writeFailure} 条 Cookie 写入失败：${safeErrorText(error)}`, "error");
        throw error;
      }
    } : null;
    let getAllInstalled = false;
    let setInstalled = !compatibleSet;
    try {
      originalCookies.getAll = compatibleGetAll;
      getAllInstalled = originalCookies.getAll === compatibleGetAll;
      if (compatibleSet) {
        originalCookies.set = compatibleSet;
        setInstalled = originalCookies.set === compatibleSet;
      }
    } catch (_) {
      // A read-only Safari API object is handled by the proxy below.
    }

    if (!getAllInstalled || !setInstalled) {
      const compatibleCookies = new Proxy({}, {
        get(_, property) {
          if (property === "getAll") return compatibleGetAll;
          if (property === "set" && compatibleSet) return compatibleSet;
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

  const completeOperation = (message, tone) => {
    if (!syncStats.active) return "";
    if (syncStats.writeSuccess + syncStats.writeFailure === 0 && syncStats.read > 0) {
      if (tone === "success") syncStats.uploadSuccess = syncStats.read;
      if (tone === "error") syncStats.uploadFailure = syncStats.read;
    }
    const hasCookieStats = syncStats.read > 0
      || syncStats.readErrors > 0
      || syncStats.writeSuccess + syncStats.writeFailure > 0;
    appendLog(`${syncStats.operation}结果：${message}`, tone);
    const summary = hasCookieStats ? countSummary() : "";
    if (summary) {
      const summaryTone = syncStats.writeFailure + syncStats.uploadFailure + syncStats.readErrors > 0
        ? "error"
        : "success";
      appendLog(summary, summaryTone);
    }
    syncStats.active = false;
    return summary;
  };

  const showFeedback = (rawMessage, isFinal = true) => {
    const baseMessage = String(rawMessage ?? "操作已完成").trim() || "操作已完成";
    let tone = feedbackTone(baseMessage);
    const summary = isFinal ? completeOperation(baseMessage, tone) : "";
    if (syncStats.writeFailure + syncStats.uploadFailure + syncStats.readErrors > 0) tone = "error";
    const message = summary ? `${baseMessage}\n${summary}` : baseMessage;
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
      text.style.whiteSpace = "pre-line";
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
      beginOperation("手动同步");
      showFeedback("正在手动同步，请稍候…", false);
    } else if (/(^|\s)(测试|test)(\s|$)/i.test(label)) {
      beginOperation("服务器测试");
      showFeedback("正在测试服务器连接…", false);
    } else if (/(^|\s)(保存|save)(\s|$)/i.test(label)) {
      beginOperation("保存设置");
      showFeedback("正在保存设置…", false);
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
