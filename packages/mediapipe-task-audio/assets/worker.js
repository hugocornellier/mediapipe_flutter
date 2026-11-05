import {installWorkerQueue, loadVerifiedRuntime, withoutNulls} from
  '../../mediapipe_core/assets/verified_runtime.js';

const loadRuntime = baseUrl =>
  loadVerifiedRuntime(new URL('runtime.json', import.meta.url), baseUrl, 'Audio');

let task;
installWorkerQueue(run, {transfers: result => result?.samples ? [result.samples.buffer] : []});

async function run(type, input, request) {
  if (type === 'create') {
    const {task: name = 'AudioClassifier', modelBytes, modelPath, delegate = 'CPU', runtimeBaseUrl, ...settings} = input;
    const {bundle, files} = await loadRuntime(runtimeBaseUrl);
    task = await bundle[name].createFromOptions(files, {
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
  if (!task) throw new Error('MediaPipe audio task is closed');
  const {text, voiceId, locale} = input;
  switch (input.op) {
    case 'transcribe':
      return JSON.stringify((await task.transcribe(input.samples, input.endOfStream)).segments);
    case 'finishStream':
      return JSON.stringify((await task.finishStream()).segments);
    case 'prewarm':
      await task.prewarm();
      return null;
    case 'listVoices':
      return JSON.stringify(await task.listVoices());
    case 'synthesize':
      return speech(await task.synthesize(text, withoutNulls({voiceId, locale})));
    case 'synthesizeStream': {
      const stream = await task.synthesizeStream(text, withoutNulls({voiceId, locale}), true);
      try {
        for (;;) {
          // Lets a cancel in, whether or not reading the next chunk has to wait.
          await new Promise(resolve => setTimeout(resolve));
          if (request.cancelled) {
            stream.cancel();
            return null;
          }
          const chunk = await stream.readNext();
          if (!chunk) return null;
          const result = speech(chunk);
          request.emit(result, [result.samples.buffer]);
        }
      } finally {
        stream.close();
      }
    }
    default:
      // One result per chunk the model reads, in order.
      return JSON.stringify(task.classify(input.samples, input.sampleRate));
  }
}

// A copy of the samples, which may be a view of the runtime's memory, and so
// can cross to the page on its own.
function speech({samples, ...result}) {
  return {samples: samples.slice(), json: JSON.stringify(result)};
}
