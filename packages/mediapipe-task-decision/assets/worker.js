import {loadVerifiedRuntime} from '../../mediapipe_core/assets/verified_runtime.js';

const loadRuntime = baseUrl =>
  loadVerifiedRuntime(new URL('runtime.json', import.meta.url), baseUrl, 'Decision');

// Google's method for each request, with its batch forms.
const methods = {
  boolean: (task, input, question) => task.evaluateBoolean(input.text, question),
  choice: (task, input, question) => task.evaluateChoice(input.text, question),
  score: (task, input, question) => task.evaluateScore(input.text, question),
  booleanBatch: (task, input, question) =>
    task.evaluateBooleanBatch(input.texts, question, input.sharedPrefix ?? undefined),
  choiceBatch: (task, input, question) =>
    task.evaluateChoiceBatch(input.texts, question, input.sharedPrefix ?? undefined),
  scoreBatch: (task, input, question) =>
    task.evaluateScoreBatch(input.texts, question, input.sharedPrefix ?? undefined),
};

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
    const {modelBytes, modelPath, delegate = 'CPU', runtimeBaseUrl, maxNumTokens} = input;
    const {bundle: {DecisionMaker}, files} = await loadRuntime(runtimeBaseUrl);
    task = await DecisionMaker.createFromOptions(files, {
      baseOptions: {delegate, ...(modelBytes ? {modelAssetBuffer: modelBytes} : {modelAssetPath: modelPath})},
      maxNumTokens,
    });
    return null;
  }
  if (type === 'close') {
    task?.close();
    task = undefined;
    return null;
  }
  if (!task) throw new Error('MediaPipe Decision Maker is closed');
  const method = methods[input.method];
  if (!method) throw new Error('Unsupported Decision Maker request: ' + input.method);
  return JSON.stringify(await method(task, input, withoutNulls(input.question)));
}

// Dart sends absent settings as null; Google's API wants them left out.
function withoutNulls(settings) {
  return Object.fromEntries(Object.entries(settings).filter(([, value]) => value != null));
}
