// One worker owns each official task. The UI never performs synchronous inference.
(() => {
  const base = new URL('.', document.currentScript.src);
  const workers = new Map();
  let next = 0;
  let totalCreated = 0;
  let totalClosed = 0;
  function fail(state, error) {
    if (state.dead) return;
    state.dead = true;
    state.worker.terminate();
    workers.delete(state.id);
    totalClosed++;
    for (const pending of state.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    state.pending.clear();
  }
  function request(state, type, input) {
    if (state.dead) {
      input?.bitmap?.close();
      return Promise.reject(new Error('MediaPipe worker is closed'));
    }
    return new Promise((resolve, reject) => {
      const id = state.next++;
      const timer = setTimeout(() => fail(state, new Error('MediaPipe worker request timed out')), 120000);
      state.pending.set(id, {resolve, reject, timer});
      const transfers = [];
      if (input?.bitmap) transfers.push(input.bitmap);
      if (input?.pixels) transfers.push(input.pixels.buffer);
      if (input?.modelBytes) transfers.push(input.modelBytes.buffer);
      try {
        state.worker.postMessage({id, type, input}, transfers);
      } catch (error) {
        clearTimeout(timer);
        state.pending.delete(id);
        input?.bitmap?.close();
        reject(error);
      }
    });
  }
  globalThis.mediapipeVision = {
    async create(options) {
      const worker = new Worker(new URL('worker.js', base), {type: 'module'});
      const id = next++;
      const state = {id, worker, pending: new Map(), next: 0, dead: false};
      workers.set(id, state);
      totalCreated++;
      worker.onmessage = ({data}) => {
        const pending = state.pending.get(data.id);
        if (!pending) return;
        clearTimeout(pending.timer);
        state.pending.delete(data.id);
        // Benchmarks set onTiming to collect the worker's per-request timings.
        if (data.timing && globalThis.mediapipeVision.onTiming) {
          globalThis.mediapipeVision.onTiming(data.timing);
        }
        if (data.error) pending.reject(new Error(data.error));
        else pending.resolve(data.result);
      };
      worker.onerror = event => {
        event.preventDefault();
        fail(state, new Error(event.message || 'MediaPipe worker failed'));
      };
      worker.onmessageerror = () => fail(state, new Error('Invalid MediaPipe worker response'));
      try {
        await request(state, 'create', options);
        return id;
      } catch (error) {
        fail(state, error);
        throw error;
      }
    },
    detect(id, input) {
      const state = workers.get(id);
      if (!state) {
        input.bitmap?.close();
        return Promise.reject(new Error('MediaPipe task is closed'));
      }
      return request(state, 'detect', input);
    },
    async close(id) {
      const state = workers.get(id);
      if (!state) return;
      try { await request(state, 'close'); }
      finally { fail(state, new Error('MediaPipe task is closed')); }
    },
    // Read-only diagnostics used by release-browser tests.
    stats() {
      return {activeWorkers: workers.size, totalCreated, totalClosed,
        pendingRequests: [...workers.values()].reduce((n, s) => n + s.pending.size, 0)};
    },
  };
})();
