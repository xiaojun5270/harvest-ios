(() => {
  const api = globalThis.browser || globalThis.chrome;
  const storage = api?.storage;
  if (!storage || storage.session || !storage.local) return;

  // Safari versions without storage.session would throw immediately after a
  // successful login when 0.3.6 caches the resolved floating-image URL. The
  // value is safe to keep in extension-local storage as a compatibility
  // fallback; the key is only a cached URL and contains no login credential.
  let installed = false;
  try {
    Object.defineProperty(storage, "session", {
      configurable: true,
      enumerable: true,
      value: storage.local
    });
    installed = Boolean(storage.session);
  } catch (_) {
    try {
      storage.session = storage.local;
      installed = Boolean(storage.session);
    } catch (_) {
      // A read-only Safari API object is handled by the proxy fallback below.
    }
  }

  if (installed) return;
  const compatibleStorage = new Proxy(storage, {
    get(target, property, receiver) {
      return property === "session" ? target.local : Reflect.get(target, property, receiver);
    }
  });
  const compatibleAPI = new Proxy(api, {
    get(target, property, receiver) {
      return property === "storage" ? compatibleStorage : Reflect.get(target, property, receiver);
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
      // The original namespace remains available if Safari locks the global.
    }
  }
})();
