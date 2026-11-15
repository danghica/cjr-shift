// The browser owns the durable snapshot. The server runs the unchanged core on
// a disposable copy; a successful localStorage write is the save boundary.
export const STORE_KEY = 'cjr-shift.store.v1';
export function createBrowserTransport(options = {}) {
  return async function request(action, data = {}) {
    const locks = options.locks ?? globalThis.navigator?.locks;
    if (!locks?.request) throw new Error('This browser cannot safely coordinate saved shifts between tabs. Use a current browser with Web Locks support.');
    return locks.request(STORE_KEY, {mode:'exclusive'}, async () => {
      let storage, raw, snapshot;
      try {
        storage = options.storage ?? globalThis.localStorage;
        raw = storage.getItem(STORE_KEY);
      } catch {
        throw new Error('Browser storage is unavailable. Allow site storage before recording shifts.');
      }
      try {
        snapshot = raw === null ? null : JSON.parse(raw);
        if (raw !== null && (!snapshot || snapshot.version !== 1 || typeof snapshot.encoding !== 'string' || !snapshot.metadata)) throw new Error();
      } catch {
        throw new Error('Saved browser data is invalid or unsupported. It has been kept unchanged; do not clear site data if you need to recover it.');
      }
      const response = await (options.fetch ?? globalThis.fetch)('/api/browser', {
        method:'POST', cache:'no-store', headers:{'Content-Type':'application/json','X-Tracker-UI':'1'},
        body:JSON.stringify({action, data, snapshot})
      });
      const result = await response.json();
      if (response.ok && result.code === 0) {
        if (!result.snapshot || result.browserStorage !== true) throw new Error('The server did not return a browser-store snapshot. Reload the page.');
        const next = JSON.stringify(result.snapshot);
        try {
          if (storage.getItem(STORE_KEY) !== raw) throw new Error('changed');
          if (next !== raw) storage.setItem(STORE_KEY, next);
        } catch (error) {
          if (error.message === 'changed') throw new Error('Saved shifts changed in another tab. Reload before trying again.');
          throw new Error('Could not save in this browser. Storage may be full or blocked. Your previous saved shifts have been kept; this change was not saved.');
        }
      }
      return {ok:response.ok, status:response.status, json:async()=>result};
    });
  };
}
export const browserRequest = createBrowserTransport();
