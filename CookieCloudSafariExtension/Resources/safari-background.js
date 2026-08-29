(() => {
  if (!globalThis.chrome && globalThis.browser) {
    globalThis.chrome = globalThis.browser;
  }

  const api = globalThis.browser || globalThis.chrome;
  const patchMethod = (owner, name, transform) => {
    if (!owner || typeof owner[name] !== "function") return;
    const original = owner[name].bind(owner);
    try {
      owner[name] = (value = {}, ...rest) => original(transform(value), ...rest);
    } catch (_) {
      // Safari may expose a non-writable API object. In that case the original
      // call remains available and the extension can continue loading.
    }
  };

  patchMethod(api?.cookies, "getAll", (details) => {
    const compatible = { ...details };
    delete compatible.partitionKey;
    return compatible;
  });

  patchMethod(api?.tabs, "create", (properties) => {
    const compatible = { ...properties };
    delete compatible.pinned;
    return compatible;
  });
})();

importScripts("background.js");
