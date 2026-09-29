async function loadRuntime(baseUrl) {
  const response = await fetch(new URL('runtime.json', import.meta.url));
  if (!response.ok) throw new Error('Unable to load MediaPipe runtime version');
  const {version} = await response.json();
  const base = baseUrl || `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-audio@${version}/`;
  return [await import(new URL('audio_bundle.mjs', base).href), new URL('wasm', base).href];
}

let task;
let operations = Promise.resolve();
self.onmessage = ({data}) => {
  // Serialize creation, requests and shutdown on the owning worker.
  operations = operations.then(async () => {
    try {
      self.postMessage({id: data.id, result: await run(data.type, data.input)});
    } catch (error) {
      self.postMessage({id: data.id, error: error?.message || String(error)});
    }
  });
};

async function run(type, input) {
  if (type === 'create') {
    const {modelBytes, modelPath, delegate = 'CPU', runtimeBaseUrl, ...settings} = input;
    const [{AudioClassifier, FilesetResolver}, wasmUrl] = await loadRuntime(runtimeBaseUrl);
    const files = await FilesetResolver.forAudioTasks(wasmUrl, true);
    task = await AudioClassifier.createFromOptions(files, {
      ...Object.fromEntries(Object.entries(settings).filter(([, value]) => value != null)),
      baseOptions: {delegate, ...(modelBytes ? {modelAssetBuffer: modelBytes} : {modelAssetPath: modelPath})},
    });
    return null;
  }
  if (type === 'close') {
    task?.close();
    task = undefined;
    return null;
  }
  if (!task) throw new Error('MediaPipe audio task is closed');
  // One result per chunk the model reads, in order.
  return JSON.stringify(task.classify(input.samples, input.sampleRate));
}
