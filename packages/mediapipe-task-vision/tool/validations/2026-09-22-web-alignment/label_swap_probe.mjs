// Does the official IMAGE task label face landmarks by the subject's anatomy
// or by the side of the picture they appear on? Runs Google's JS task on the
// fixture portrait and on its horizontal flip in Chromium and reports, for each
// alignment probe, how far the flip's landmark lies from the reflection of the
// original's same landmark and of its left/right partner.
//
// Serve the release gallery first (python3.12 -B gallery/tool/web_server.py),
// then from the repository root:
//   node packages/mediapipe-task-vision/tool/validations/2026-09-22-web-alignment/label_swap_probe.mjs
import {createRequire} from 'node:module';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../..');
const {chromium} = createRequire(path.join(repo, 'gallery/tool/browser/package.json'))('playwright');
const base = process.argv[2] || 'http://localhost:8866/mediapipe_flutter/';

const browser = await chromium.launch({channel: 'chromium', headless: true});
const page = await browser.newPage();
await page.goto(base);
const found = await page.evaluate(async () => {
  const runtime = new URL('assets/packages/mediapipe_flutter_vision_web/assets/runtime/', document.baseURI);
  const {FilesetResolver, FaceLandmarker} = await import(new URL('vision_bundle.mjs', runtime));
  const files = await FilesetResolver.forVisionTasks(new URL('wasm', runtime).href);
  const task = await FaceLandmarker.createFromOptions(files, {
    baseOptions: {delegate: 'CPU', modelAssetPath: new URL('assets/assets/models/face_landmarker.task', document.baseURI).href},
    runningMode: 'IMAGE', numFaces: 1,
  });
  const image = await createImageBitmap(await (await fetch(new URL('assets/assets/samples/portrait.jpg', document.baseURI))).blob());
  const canvas = new OffscreenCanvas(image.width, image.height);
  const context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  const plain = task.detect(canvas).faceLandmarks[0];
  context.setTransform(-1, 0, 0, 1, image.width, 0);
  context.drawImage(image, 0, 0);
  const flipped = task.detect(canvas).faceLandmarks[0];
  task.close();
  return {width: image.width, height: image.height,
    plain: plain.map(p => [p.x, p.y]), flipped: flipped.map(p => [p.x, p.y])};
});
const browserVersion = browser.version();
await browser.close();

const partners = {1: 1, 152: 152, 10: 10, 468: 473, 473: 468, 61: 291, 291: 61, 33: 263, 263: 33};
const {width, height} = found;
const diagonal = Math.hypot(width, height);
const pixels = ([x, y]) => [x * width, y * height];
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]) / diagonal;
const probes = {};
for (const [index, partner] of Object.entries(partners)) {
  const [x, y] = pixels(found.plain[index]);
  const reflected = [width - x, y];
  probes[index] = {
    same_label: distance(pixels(found.flipped[index]), reflected),
    partner_label: distance(pixels(found.flipped[partner]), reflected),
  };
}
console.log(JSON.stringify({
  image: 'gallery assets/samples/portrait.jpg (landmark-ex1.jpg)', image_size: [width, height],
  browser: 'chromium ' + browserVersion, delegate: 'CPU', running_mode: 'IMAGE',
  unit: 'fraction of the image diagonal', probes,
}, null, 2));
