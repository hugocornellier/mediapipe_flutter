import {FilesetResolver, FaceLandmarker} from './runtime/vision_bundle.mjs';

let task;
let operations = Promise.resolve();
self.onmessage = ({data}) => {
  // Serialize initialization, frames and shutdown on the owning worker.
  operations = operations.then(async () => {
    try {
      const result = await run(data.type, data.input);
      self.postMessage({id: data.id, result});
    } catch (error) {
      self.postMessage({id: data.id, error: error?.message || String(error)});
    }
  });
};
async function run(type, input) {
  if (type === 'create') {
    const files = await FilesetResolver.forVisionTasks(new URL('./runtime/wasm', import.meta.url).href, true);
    const {modelBytes, modelPath, ...settings} = input;
    task = await FaceLandmarker.createFromOptions(files, {
      ...settings,
      baseOptions: {
        delegate: 'CPU',
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
    const result = input.timestamp == null
      ? task.detect(source, processing)
      : task.detectForVideo(source, input.timestamp, processing);
    return JSON.stringify({width: source.width, height: source.height,
      timestamp: input.timestamp, result});
  } finally {
    owned?.close();
  }
}
