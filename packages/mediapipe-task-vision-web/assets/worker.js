import {FilesetResolver, FaceLandmarker} from './runtime/vision_bundle.mjs';

let task;
let operations = Promise.resolve();
self.onmessage = ({data}) => {
  // Serialize initialization, frames and shutdown on the owning worker.
  operations = operations.then(async () => {
    try {
      const timing = {received: performance.timeOrigin + performance.now()};
      const result = await run(data.type, data.input, timing);
      timing.sent = performance.timeOrigin + performance.now();
      self.postMessage({id: data.id, result, timing}, result?.landmarks ? [result.landmarks.buffer] : []);
    } catch (error) {
      self.postMessage({id: data.id, error: error?.message || String(error)});
    }
  });
};
async function run(type, input, timing) {
  if (type === 'create') {
    const files = await FilesetResolver.forVisionTasks(new URL('./runtime/wasm', import.meta.url).href, true);
    const {modelBytes, modelPath, delegate, ...settings} = input;
    if (delegate !== 'CPU' && delegate !== 'GPU') throw new Error('Invalid FaceLandmarker delegate');
    if (typeof OffscreenCanvas === 'undefined') {
      throw new Error('FaceLandmarker requires OffscreenCanvas in a browser worker.');
    }
    // The bundled runtime picks its own canvas by sniffing the user agent, and
    // reads every WebKit browser without a Version/NN token as Safari 16. Firefox
    // and Chrome on iOS land there, and its fallback calls document.createElement
    // inside a worker, where there is no document. Supplying the canvas keeps that
    // branch unreachable.
    const canvas = new OffscreenCanvas(1, 1);
    if (delegate === 'GPU' && !canvas.getContext('webgl2')) {
      throw new Error('GPU FaceLandmarker requires WebGL 2 in a browser worker. Select CPU or enable browser hardware acceleration.');
    }
    task = await FaceLandmarker.createFromOptions(files, {
      ...settings,
      canvas,
      baseOptions: {
        delegate,
        ...(modelBytes ? {modelAssetBuffer: modelBytes} : {modelAssetPath: modelPath}),
      },
    });
    return null;
  }
  if (type === 'close') {
    task?.close();
    task = undefined;
    return null;
  }
  let source = input.bitmap;
  let owned = input.bitmap;
  try {
    if (!task) throw new Error('FaceLandmarker is closed');
    if (input.path) {
      const response = await fetch(input.path);
      if (!response.ok) throw new Error('Image load failed: ' + response.status);
      source = owned = await createImageBitmap(await response.blob());
    } else if (input.pixels) {
      const rgba = new Uint8ClampedArray(input.width * input.height * 4);
      const channels = input.format === 'rgb' ? 3 : 4;
      const bgra = input.format === 'bgra';
      for (let y = 0; y < input.height; y++) {
        for (let x = 0; x < input.width; x++) {
          const from = y * input.stride + x * channels;
          const to = (y * input.width + x) * 4;
          rgba[to] = input.pixels[from + (bgra ? 2 : 0)];
          rgba[to + 1] = input.pixels[from + 1];
          rgba[to + 2] = input.pixels[from + (bgra ? 0 : 2)];
          rgba[to + 3] = channels === 3 ? 255 : input.pixels[from + 3];
        }
      }
      source = new ImageData(rgba, input.width, input.height);
    }
    const processing = {rotationDegrees: ((input.rotation % 360) + 360) % 360};
    const started = performance.now();
    const result = input.timestamp == null
      ? task.detect(source, processing)
      : task.detectForVideo(source, input.timestamp, processing);
    const inferred = performance.now();
    const packed = pack(result);
    const json = JSON.stringify({width: source.width, height: source.height,
      timestamp: input.timestamp, counts: packed?.counts,
      result: packed ? {...result, faceLandmarks: []} : result});
    timing.inference = inferred - started;
    timing.serialize = performance.now() - inferred;
    timing.timestamp = input.timestamp;
    return {json, landmarks: packed?.values};
  } finally {
    owned?.close();
  }
}
// Face landmarks as x, y, z, visibility, presence per point (NaN when absent),
// transferred rather than serialized. Named landmarks stay in the JSON.
function pack(result) {
  const faces = result.faceLandmarks ?? [];
  if (faces.some(face => face.some(point => point.name != null))) return null;
  const counts = faces.map(face => face.length);
  const values = new Float64Array(counts.reduce((a, b) => a + b, 0) * 5);
  let at = 0;
  for (const face of faces) {
    for (const point of face) {
      values[at++] = point.x;
      values[at++] = point.y;
      values[at++] = point.z;
      values[at++] = point.visibility ?? NaN;
      values[at++] = point.presence ?? NaN;
    }
  }
  return {counts, values};
}
