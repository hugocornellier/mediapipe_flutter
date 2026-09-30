import {loadVerifiedRuntime} from '../../mediapipe_core/assets/verified_runtime.js';

const loadRuntime = baseUrl =>
  loadVerifiedRuntime(new URL('runtime.json', import.meta.url), baseUrl, 'Audio');

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
    const {bundle: {AudioClassifier}, files} = await loadRuntime(runtimeBaseUrl);
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
