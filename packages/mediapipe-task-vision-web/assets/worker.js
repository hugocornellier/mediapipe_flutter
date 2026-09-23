import {
  FilesetResolver, FaceDetector, FaceLandmarker, GestureRecognizer, HandLandmarker,
  HolisticLandmarker, ImageClassifier, ImageEmbedder, ImageSegmenter,
  InteractiveSegmenter, InteractiveSegmenterLegacy, ObjectDetector, PoseLandmarker,
} from './runtime/vision_bundle.mjs';

// Each task: Google's class, its IMAGE and VIDEO methods, and the result field
// holding its image landmarks, which travel packed; everything else in the
// result travels as JSON. Holistic's several parts all travel as JSON. Mask
// fields name their bytes per value; masks travel as transferred buffers.
const TASKS = {
  face_landmarker: {name: 'FaceLandmarker', type: FaceLandmarker, landmarks: 'faceLandmarks'},
  hand_landmarker: {name: 'HandLandmarker', type: HandLandmarker, landmarks: 'landmarks'},
  pose_landmarker: {name: 'PoseLandmarker', type: PoseLandmarker, landmarks: 'landmarks',
    masks: {segmentationMasks: 4}},
  gesture_recognizer: {name: 'GestureRecognizer', type: GestureRecognizer, landmarks: 'landmarks',
    image: 'recognize', video: 'recognizeForVideo'},
  holistic_landmarker: {name: 'HolisticLandmarker', type: HolisticLandmarker,
    masks: {poseSegmentationMasks: 4}},
  face_detector: {name: 'FaceDetector', type: FaceDetector},
  object_detector: {name: 'ObjectDetector', type: ObjectDetector},
  image_classifier: {name: 'ImageClassifier', type: ImageClassifier,
    image: 'classify', video: 'classifyForVideo'},
  // Quantized embeddings are typed arrays, which JSON would turn into objects.
  image_embedder: {name: 'ImageEmbedder', type: ImageEmbedder,
    image: 'embed', video: 'embedForVideo',
    json: result => ({...result, embeddings: result.embeddings.map(e => ({
      ...e,
      floatEmbedding: e.floatEmbedding && Array.from(e.floatEmbedding),
      quantizedEmbedding: e.quantizedEmbedding && Array.from(e.quantizedEmbedding),
    }))})},
  image_segmenter: {name: 'ImageSegmenter', type: ImageSegmenter,
    image: 'segment', video: 'segmentForVideo',
    masks: {confidenceMasks: 4, categoryMask: 1}, labels: true,
    json: result => ({...result, qualityScores: result.qualityScores && Array.from(result.qualityScores)})},
  // IMAGE only, for the object under a keypoint. The Dart API reports no
  // labels for it, as Google's desktop bindings have none.
  // Its model must arrive as a URL: Google's 1.0.1 task drops a model given as
  // a buffer (upstream-issues.md UP-021).
  interactive_segmenter_legacy: {name: 'InteractiveSegmenterLegacy', type: InteractiveSegmenterLegacy,
    masks: {confidenceMasks: 4, categoryMask: 1}, modelAsUrl: true,
    call: (task, source, input, processing) =>
      task.segment(source, {keypoint: {x: input.keypoint[0], y: input.keypoint[1]}}, processing),
    json: result => ({...result, qualityScores: result.qualityScores && Array.from(result.qualityScores),
      labels: []})},
  // Stateful MagicTouch: setImage keeps an image, then each request carries a
  // full stroke history and returns one float mask.
  interactive_segmenter: {name: 'InteractiveSegmenter', type: InteractiveSegmenter,
    stateful: true},
};

let task;
let labels;
let spec = TASKS.face_landmarker;
let operations = Promise.resolve();
self.onmessage = ({data}) => {
  // Serialize initialization, frames and shutdown on the owning worker.
  operations = operations.then(async () => {
    try {
      const timing = {received: performance.timeOrigin + performance.now()};
      const result = await run(data.type, data.input, timing);
      timing.sent = performance.timeOrigin + performance.now();
      const transfers = result?.masks ? [...result.masks] : [];
      if (result?.landmarks) transfers.push(result.landmarks.buffer);
      self.postMessage({id: data.id, result, timing}, transfers);
    } catch (error) {
      self.postMessage({id: data.id, error: error?.message || String(error)});
    }
  });
};
async function run(type, input, timing) {
  if (type === 'create') {
    const files = await FilesetResolver.forVisionTasks(new URL('./runtime/wasm', import.meta.url).href, true);
    const {modelBytes, modelPath, delegate, task: name = 'face_landmarker', ...settings} = input;
    spec = TASKS[name];
    if (!spec) throw new Error('Unsupported MediaPipe task: ' + name);
    if (delegate !== 'CPU' && delegate !== 'GPU') throw new Error('Invalid ' + spec.name + ' delegate');
    if (typeof OffscreenCanvas === 'undefined') {
      throw new Error(spec.name + ' requires OffscreenCanvas in a browser worker.');
    }
    // The bundled runtime picks its own canvas by sniffing the user agent, and
    // reads every WebKit browser without a Version/NN token as Safari 16. Firefox
    // and Chrome on iOS land there, and its fallback calls document.createElement
    // inside a worker, where there is no document. Supplying the canvas keeps that
    // branch unreachable.
    const canvas = new OffscreenCanvas(1, 1);
    if (delegate === 'GPU' && !canvas.getContext('webgl2')) {
      throw new Error('GPU ' + spec.name + ' requires WebGL 2 in a browser worker. Select CPU or enable browser hardware acceleration.');
    }
    const url = modelBytes && spec.modelAsUrl ? URL.createObjectURL(new Blob([modelBytes])) : null;
    try {
      task = await spec.type.createFromOptions(files, {
        ...settings,
        canvas,
        baseOptions: {
          delegate,
          ...(url ? {modelAssetPath: url}
            : modelBytes ? {modelAssetBuffer: modelBytes} : {modelAssetPath: modelPath}),
        },
      });
    } finally {
      if (url) URL.revokeObjectURL(url);
    }
    labels = spec.labels ? task.getLabels() : undefined;
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
    if (!task) throw new Error(spec.name + ' is closed');
    if (spec.stateful && input.strokes) return segmentStrokes(input.strokes, timing);
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
    if (spec.stateful) {
      task.setImage(source);
      return {json: JSON.stringify({result: {}})};
    }
    const processing = {rotationDegrees: ((input.rotation % 360) + 360) % 360};
    if (input.region) {
      const [left, top, right, bottom] = input.region;
      processing.regionOfInterest = {left, top, right, bottom};
    }
    const started = performance.now();
    const result = spec.call ? spec.call(task, source, input, processing)
      : input.timestamp == null
        ? task[spec.image ?? 'detect'](source, processing)
        : task[spec.video ?? 'detectForVideo'](source, input.timestamp, processing);
    const inferred = performance.now();
    const packed = spec.landmarks ? pack(result[spec.landmarks] ?? []) : null;
    const masks = [];
    let plain = spec.json ? spec.json(result) : result;
    try {
      plain = {...plain, ...copyMasks(result, masks)};
    } finally {
      closeMasks(result);
    }
    if (labels) plain.labels = labels;
    const json = JSON.stringify({width: source.width, height: source.height,
      timestamp: input.timestamp, counts: packed?.counts,
      result: packed ? {...plain, [spec.landmarks]: []} : plain});
    timing.inference = inferred - started;
    timing.serialize = performance.now() - inferred;
    timing.timestamp = input.timestamp;
    return {json, landmarks: packed?.values, masks};
  } finally {
    owned?.close();
  }
}
// Each stroke arrives as [brush mode, [x, y, ...], completed]; the modes are
// Google's numeric BrushMode values.
function segmentStrokes(strokes, timing) {
  const started = performance.now();
  const mask = task.segment(strokes.map(([brushMode, xy, isCompleted]) => ({
    brushMode, isCompleted,
    point: Array.from({length: xy.length >> 1}, (_, i) => ({x: xy[2 * i], y: xy[2 * i + 1]})),
  })));
  try {
    timing.inference = performance.now() - started;
    const values = mask.getAsFloat32Array().slice();
    return {json: JSON.stringify({result: {confidenceMasks: [[mask.width, mask.height, 4, 0]]}}),
      masks: [values.buffer]};
  } finally {
    mask.close();
  }
}
// Copies each of the spec's masks into [buffers], naming it in the JSON as
// [width, height, bytes per value, index]: float32 confidences or uint8
// categories. The copies outlive the result, which frees Google's masks.
function copyMasks(result, buffers) {
  const named = {};
  for (const [field, depth] of Object.entries(spec.masks ?? {})) {
    const value = result[field];
    if (value == null) continue;
    const copy = mask => {
      const values = depth === 1 ? mask.getAsUint8Array() : mask.getAsFloat32Array();
      buffers.push(values.slice().buffer);
      return [mask.width, mask.height, depth, buffers.length - 1];
    };
    named[field] = Array.isArray(value) ? value.map(copy) : copy(value);
  }
  return named;
}
// Frees Google's masks: a segmenter result closes its own; in 1.0.1 the
// landmarker results have no close(), so their masks are closed one by one.
function closeMasks(result) {
  if (typeof result.close === 'function') return result.close();
  for (const field of Object.keys(spec.masks ?? {})) {
    const value = result[field];
    for (const mask of Array.isArray(value) ? value : value ? [value] : []) mask.close();
  }
}
// Image landmarks as x, y, z, visibility, presence per point (NaN when absent),
// transferred rather than serialized. Named landmarks stay in the JSON.
function pack(subjects) {
  if (subjects.some(points => points.some(point => point.name != null))) return null;
  const counts = subjects.map(points => points.length);
  const values = new Float64Array(counts.reduce((a, b) => a + b, 0) * 5);
  let at = 0;
  for (const points of subjects) {
    for (const point of points) {
      values[at++] = point.x;
      values[at++] = point.y;
      values[at++] = point.z;
      values[at++] = point.visibility ?? NaN;
      values[at++] = point.presence ?? NaN;
    }
  }
  return {counts, values};
}
