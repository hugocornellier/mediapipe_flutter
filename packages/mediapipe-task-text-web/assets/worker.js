import {FilesetResolver, LanguageDetector, TextClassifier, TextEmbedder} from './runtime/text_bundle.mjs';

// Google's class and the method that runs one text, per task.
const TASKS = {
  text_classifier: {type: TextClassifier, run: (task, text) => task.classify(text)},
  text_embedder: {type: TextEmbedder, run: (task, text) => task.embed(text)},
  language_detector: {type: LanguageDetector, run: (task, text) => task.detect(text)},
};

let task;
let spec;
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
    const {task: name, modelBytes, modelPath, delegate = 'CPU', ...settings} = input;
    spec = TASKS[name];
    if (!spec) throw new Error('Unsupported MediaPipe text task: ' + name);
    const files = await FilesetResolver.forTextTasks(new URL('./runtime/wasm', import.meta.url).href, true);
    task = await spec.type.createFromOptions(files, {
      ...withoutNulls(settings),
      baseOptions: {delegate, ...(modelBytes ? {modelAssetBuffer: modelBytes} : {modelAssetPath: modelPath})},
    });
    return null;
  }
  if (type === 'close') {
    task?.close();
    task = undefined;
    return null;
  }
  if (!task) throw new Error('MediaPipe text task is closed');
  // Quantized embeddings are typed arrays, which JSON would turn into objects.
  return JSON.stringify(spec.run(task, input.text),
    (_, value) => value instanceof Uint8Array ? Array.from(value) : value);
}

// Dart sends absent options as null; Google's setters want them left out.
function withoutNulls(settings) {
  return Object.fromEntries(Object.entries(settings).filter(([, value]) => value != null));
}
