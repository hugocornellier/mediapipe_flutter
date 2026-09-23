import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, firefox} from 'playwright';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const argumentsMap = Object.fromEntries(process.argv.slice(2).map(arg => arg.replace(/^--/, '').split('=')));
const browserName = argumentsMap.browser || 'chromium';
const suite = argumentsMap.suite || 'all';
const delegate = argumentsMap.delegate === 'gpu' ? 'GPU' : 'CPU';
// The live demo the camera suite drives. Probes and mirror partners match
// AlignmentProbes in gallery/lib/live/live_subjects.dart: the official IMAGE
// task labels a face's landmarks by the side of the picture they appear on,
// so across a mirror it reports each probe's left/right partner, while a hand
// keeps its numbering (only its handedness flips).
const TASKS = {
  face: {tile: /Live Face Landmarker/, points: '478', fixture: 'web-camera.y4m',
    task: 'FaceLandmarker', model: 'face_landmarker.task', landmarks: 'faceLandmarks',
    options: {numFaces: 1},
    partners: {1: 1, 152: 152, 10: 10, 468: 473, 473: 468, 61: 291, 291: 61, 33: 263, 263: 33}},
  hand: {tile: /Live Hand Landmarker/, points: '21', fixture: 'web-camera-hand.y4m',
    task: 'HandLandmarker', model: 'hand_landmarker.task', landmarks: 'landmarks',
    options: {numHands: 2},
    partners: {0: 0, 4: 4, 8: 8, 12: 12, 16: 16, 20: 20, 5: 5, 17: 17}},
};
const taskName = argumentsMap.task || 'face';
const subject = TASKS[taskName];
assert.ok(subject, 'Unknown --task ' + taskName);
const base = argumentsMap['base-url'] || 'http://localhost:8866/mediapipe_flutter/';
// The gallery publishes its per-frame state for these checks only on request.
const gallery = base + (base.includes('?') ? '&' : '?') + 'test-hooks';
const apiBase = argumentsMap['api-url'] || 'http://localhost:8866/api-probe/';
const evidence = path.join(repo, 'build/codex-tmp/web-browser-' + browserName +
  (delegate === 'GPU' ? '-gpu' : '') + (taskName === 'face' ? '' : '-' + taskName));
fs.mkdirSync(evidence, {recursive: true});
const report = {browser: browserName, delegate, suite, task: taskName, checks: [], physical_webcam_tested: false,
  software_webgl: browserName === 'chromium' && process.platform === 'linux'};
const logs = [];
const browsers = [];

async function launch(deviceCount = 2, useFile = true) {
  const options = browserName === 'chromium' ? {
    // The lightweight headless shell rejects getUserMedia. Full Chromium's
    // modern headless mode exercises the same capture APIs as normal Chrome.
    channel: 'chromium',
    args: ['--use-fake-device-for-media-stream=device-count=' + deviceCount,
      ...(process.platform === 'linux' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : []),
      ...(useFile ? ['--use-file-for-fake-video-capture=' + path.join(repo, 'build/codex-tmp', subject.fixture)] : [])],
  } : {
    // Hosted Linux has no GPU. Permit Mesa's software WebGL context for the
    // official CPU task's image upload/preprocessing (not GPU inference).
    firefoxUserPrefs: process.platform === 'linux' ? {'webgl.force-enabled': true} : {},
  };
  options.headless = argumentsMap.headed !== 'true';
  const browser = await (browserName === 'firefox' ? firefox : chromium).launch(options);
  browsers.push(browser);
  report.browser_version = browser.version();
  return browser;
}

function observe(page) {
  page.on('console', msg => logs.push({type: msg.type(), text: msg.text()}));
  page.on('pageerror', error => logs.push({type: 'pageerror', text: error.stack}));
  page.on('response', response => {
    if (response.status() >= 400) logs.push({type: 'http', status: response.status(), url: response.url()});
  });
}

// [arg] is passed to [condition], which runs in the page.
async function wait(page, condition, arg = null, timeout = 60000) {
  await page.waitForFunction(condition, arg, {timeout});
}

// Same criterion as gallery/integration_test/support/alignment_oracle.dart:
// median probe deviation, and any single probe, as a fraction of the preview
// diagonal.
const alignmentTolerance = 0.015;
const alignmentOutlierTolerance = 0.03;

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

// Google's official IMAGE task, run in the page over PNG screenshot pixels.
async function detectScreenshot(page, png) {
  return page.evaluate(async ({base64, spec}) => {
    const runtime = new URL('assets/packages/mediapipe_flutter_vision_web/assets/runtime/', document.baseURI);
    const bundle = await import(new URL('vision_bundle.mjs', runtime));
    const files = await bundle.FilesetResolver.forVisionTasks(new URL('wasm', runtime).href);
    const task = await bundle[spec.task].createFromOptions(files, {
      baseOptions: {delegate: 'CPU', modelAssetPath: new URL('assets/assets/models/' + spec.model, document.baseURI).href},
      runningMode: 'IMAGE', ...spec.options,
    });
    const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes], {type: 'image/png'}));
    try {
      const found = task.detect(bitmap)[spec.landmarks];
      return {width: bitmap.width, height: bitmap.height, subjects: found.length,
        landmarks: found[0]?.map(p => [p.x, p.y]) ?? []};
    } finally {bitmap.close(); task.close();}
  }, {base64: png.toString('base64'), spec: {task: subject.task, model: subject.model,
    landmarks: subject.landmarks, options: subject.options}});
}

// The Dart overlay-alignment oracle, in the browser. Screenshot the preview
// with the overlay hidden, run the official IMAGE task over those pixels and
// compare the subject it finds with where the overlay draws the live result. The
// web view publishes the probes from the painter's own transform, relative to
// the overlay's box on the page; the screenshot is cropped to that box, so a
// video that is not under its overlay fails too. The mirrored hypothesis
// reflects each probe about the fitted frame's centre line, as the Dart
// oracle does, so a failure says which one the screen matches; each
// hypothesis reads the on-screen landmarks under the labels it implies.
async function alignmentCheck(page) {
  const overlay = () => page.locator('video').evaluate(video => ({
    subjects: video.getAttribute('data-subjects'),
    box: JSON.parse(video.getAttribute('data-overlay-box')),
    frame: JSON.parse(video.getAttribute('data-frame-box')),
    probes: JSON.parse(video.getAttribute('data-probes')),
    mirror: video.getAttribute('data-mirror') === 'true',
    rotation: Number(video.getAttribute('data-rotation')),
    video: (({x, y, width, height}) => [x, y, width, height])(video.getBoundingClientRect()),
    videoTransform: video.style.transform,
    dpr: window.devicePixelRatio,
  }));
  const connections = page.getByRole('button', {name: 'Connections'});
  await connections.click();
  // Keep the pointer, and any tooltip it raises, away from the preview.
  await page.mouse.move(1, page.viewportSize().height - 1);
  try {
    for (let attempt = 1; ; attempt++) {
      await wait(page, () => {
        const video = document.querySelector('video');
        return video?.getAttribute('data-subjects') === '1' && video.hasAttribute('data-probes');
      });
      // Two animation frames: Flutter has painted the hidden overlay.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const before = await overlay();
      const x = Math.floor(before.box[0]), y = Math.floor(before.box[1]);
      const clip = {x, y, width: Math.ceil(before.box[0] + before.box[2]) - x,
        height: Math.ceil(before.box[1] + before.box[3]) - y};
      const png = await page.screenshot({clip});
      const after = await overlay();
      const observed = await detectScreenshot(page, png);
      // The fixture alternates subject and blank; retry a capture that met a blank.
      if ((after.subjects !== '1' || observed.subjects !== 1) && attempt < 5) continue;
      fs.writeFileSync(path.join(evidence, 'alignment-preview-without-overlay.png'), png);
      const measurement = {
        observed_subjects: observed.subjects,
        crop_size: [observed.width, observed.height],
        tolerance: alignmentTolerance,
        outlier_tolerance: alignmentOutlierTolerance,
        attempts: attempt,
        overlay_box_css: before.box,
        video_rect_css: before.video,
        frame_box_css: before.frame,
        device_pixel_ratio: before.dpr,
        frame_rotation: before.rotation,
        mirror: before.mirror,
        video_transform: before.videoTransform,
      };
      if (observed.subjects !== 1) return measurement;
      const {dpr} = before;
      const diagonal = Math.hypot(before.box[2], before.box[3]) * dpr;
      const axis = before.frame[0] + before.frame[2] / 2;
      const distance = (index, mirror, probeX, probeY) => {
        const [seenX, seenY] = observed.landmarks[mirror ? subject.partners[index] : index];
        return Math.hypot((before.box[0] - clip.x + probeX) * dpr - seenX * observed.width,
          (before.box[1] - clip.y + probeY) * dpr - seenY * observed.height) / diagonal;
      };
      const distances = {}, mirrored = {};
      let drift = 0;
      for (const [index, [probeX, probeY]] of Object.entries(before.probes)) {
        assert.ok(index in subject.partners, 'no mirror partner for probe ' + index);
        distances[index] = distance(index, before.mirror, probeX, probeY);
        mirrored[index] = distance(index, !before.mirror, 2 * axis - probeX, probeY);
        const [laterX, laterY] = after.probes?.[index] ?? [probeX, probeY];
        drift = Math.max(drift, Math.hypot(laterX - probeX, laterY - probeY));
      }
      Object.assign(measurement, {
        median: median(Object.values(distances)),
        maximum: Math.max(...Object.values(distances)),
        median_if_mirrored: median(Object.values(mirrored)),
        probe_drift_during_capture_css: drift,
        distances,
        distances_if_mirrored: mirrored,
      });
      measurement.aligned = measurement.median <= alignmentTolerance &&
        measurement.maximum <= alignmentOutlierTolerance;
      return measurement;
    }
  } finally {
    await connections.click();
  }
}

async function apiChecks() {
  const browser = await launch();
  const page = await browser.newPage();
  observe(page);
  await page.goto(apiBase + (delegate === 'GPU' ? '?delegate=gpu' : ''));
  await wait(page, () => window.mediapipeApiTestReport);
  const api = await page.evaluate(() => window.mediapipeApiTestReport);
  fs.writeFileSync(path.join(evidence, 'api-report.json'), JSON.stringify(api, null, 2));
  assert.equal(api.status, 'passed', JSON.stringify(api));
  const direct = await page.evaluate(async delegate => {
    const runtime = new URL('assets/packages/mediapipe_flutter_vision_web/assets/runtime/', document.baseURI);
    const {FilesetResolver, FaceLandmarker} = await import(new URL('vision_bundle.mjs', runtime));
    const files = await FilesetResolver.forVisionTasks(new URL('wasm', runtime).href);
    const task = await FaceLandmarker.createFromOptions(files, {
      baseOptions: {delegate, modelAssetPath: new URL('assets/assets/models/face_landmarker.task', document.baseURI).href},
      runningMode: 'IMAGE', numFaces: 1, outputFaceBlendshapes: true, outputFacialTransformationMatrixes: true,
    });
    const response = await fetch(new URL('assets/assets/samples/portrait.jpg', document.baseURI));
    const bitmap = await createImageBitmap(await response.blob());
    try {
      const result = task.detect(bitmap);
      return {
        width: bitmap.width, height: bitmap.height,
        landmarks: result.faceLandmarks[0].map(p => [p.x, p.y, p.z]),
        blendshapes: result.faceBlendshapes[0].categories.map(c => c.score),
        matrix: result.facialTransformationMatrixes[0].data,
      };
    } finally {bitmap.close(); task.close();}
  }, delegate);
  fs.writeFileSync(path.join(evidence, 'official-js-reference.json'), JSON.stringify(direct, null, 2));
  assert.equal(api.image.width, direct.width);
  assert.equal(api.image.height, direct.height);
  const errors = {};
  for (const group of ['landmarks', 'blendshapes', 'matrix']) {
    const actual = api.image[group].flat();
    const expected = direct[group].flat();
    assert.equal(actual.length, expected.length);
    errors[group] = Math.max(...actual.map((value, i) => Math.abs(value - expected[i])));
    assert.ok(errors[group] < 1e-5, group + ' differs from official JavaScript: ' + errors[group]);
  }
  // Hand Landmarker through the Dart API versus Google's JavaScript on the
  // same image, runtime and delegate.
  const hand = await page.evaluate(async delegate => {
    const runtime = new URL('assets/packages/mediapipe_flutter_vision_web/assets/runtime/', document.baseURI);
    const {FilesetResolver, HandLandmarker} = await import(new URL('vision_bundle.mjs', runtime));
    const files = await FilesetResolver.forVisionTasks(new URL('wasm', runtime).href);
    const task = await HandLandmarker.createFromOptions(files, {
      baseOptions: {delegate, modelAssetPath: new URL('assets/assets/models/hand_landmarker.task', document.baseURI).href},
      runningMode: 'IMAGE', numHands: 2,
    });
    const response = await fetch(new URL('assets/assets/samples/hands.jpg', document.baseURI));
    const bitmap = await createImageBitmap(await response.blob());
    try {
      const result = task.detect(bitmap);
      return {
        width: bitmap.width, height: bitmap.height,
        landmarks: result.landmarks.flatMap(points => points.map(p => [p.x, p.y, p.z])),
        world: result.worldLandmarks.flatMap(points => points.map(p => [p.x, p.y, p.z])),
        handedness: result.handedness.map(categories => categories[0].score),
      };
    } finally {bitmap.close(); task.close();}
  }, delegate);
  fs.writeFileSync(path.join(evidence, 'official-js-hand-reference.json'), JSON.stringify(hand, null, 2));
  assert.equal(api.hand.width, hand.width);
  assert.equal(api.hand.height, hand.height);
  const handErrors = {};
  for (const group of ['landmarks', 'world', 'handedness']) {
    const actual = api.hand[group].flat();
    const expected = hand[group].flat();
    assert.ok(expected.length > 0, 'official JavaScript found no hand');
    assert.equal(actual.length, expected.length, group + ' count differs from official JavaScript');
    handErrors[group] = Math.max(...actual.map((value, i) => Math.abs(value - expected[i])));
    assert.ok(handErrors[group] < 1e-5, 'hand ' + group + ' differs from official JavaScript: ' + handErrors[group]);
  }
  assert.deepEqual(await page.evaluate(() => mediapipeVision.stats().activeWorkers), 0);
  report.official_js_maximum_absolute_error = errors;
  report.official_js_hand_maximum_absolute_error = handErrors;
  report.checks.push(...api.checks, 'same-browser-official-js-reference', 'same-browser-official-js-hand-reference');
  await page.screenshot({path: path.join(evidence, 'api.png')});
  await browser.close();
}

async function iosUserAgentCpuCheck() {
  const userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/133.0 Mobile/15E148 Safari/605.1.15';
  const browser = await launch();
  const context = await browser.newContext({userAgent});
  const page = await context.newPage();
  observe(page);
  // Failed creation terminates the worker before Playwright can inspect it.
  // Hold only the create request, then release it unchanged after observation.
  await page.addInitScript(() => {
    const postMessage = Worker.prototype.postMessage;
    const pending = [];
    Worker.prototype.postMessage = function(...args) {
      if (args[0]?.type === 'create') pending.push([this, args]);
      else postMessage.apply(this, args);
    };
    window.testResumeTaskCreation = () => {
      Worker.prototype.postMessage = postMessage;
      for (const [worker, args] of pending) postMessage.apply(worker, args);
    };
  });
  const result = report.ios_user_agent_cpu = {
    override_method: 'browser-context',
    requested_user_agent: userAgent,
    physical_ios_tested: false,
  };
  // Inspect the actual module worker used by the Dart API, not just the page.
  const workerState = page.waitForEvent('worker', {
    predicate: worker => worker.url().endsWith('/mediapipe_flutter_vision_web/assets/worker.js'),
  }).then(worker => worker.evaluate(() => ({
    user_agent: navigator.userAgent,
    document_type: typeof document,
    offscreen_canvas_type: typeof OffscreenCanvas,
  })));
  try {
    await page.goto(apiBase);
    result.worker = await workerState;
    assert.equal(result.worker.user_agent, userAgent, 'iOS Firefox UA must reach the task worker');
    assert.equal(result.worker.document_type, 'undefined');
    assert.equal(result.worker.offscreen_canvas_type, 'function');
    await page.evaluate(() => window.testResumeTaskCreation());
    await wait(page, () => window.mediapipeApiTestReport);
    result.api = await page.evaluate(() => window.mediapipeApiTestReport);
    assert.equal(result.api.status, 'passed',
      'iOS Firefox UA CPU task must construct and run: ' + (result.api.error || JSON.stringify(result.api)));
    assert.equal(await page.evaluate(() => mediapipeVision.stats().activeWorkers), 0);
    report.checks.push('ios-firefox-user-agent-cpu-worker-construction-and-inference');
  } finally {
    fs.writeFileSync(path.join(evidence, 'ios-user-agent-cpu.json'), JSON.stringify(result, null, 2));
    await context.close();
    await browser.close();
  }
}

async function installCaptureObservations(page, emulateMobileFacing = false) {
  await page.addInitScript(emulateFacing => {
    window.testCaptureTracks = [];
    window.testFrameCallbacks = new Set();
    window.testWorkers = [];
    window.testCaptureDiagnostics = [];
    const NativeWorker = window.Worker;
    window.Worker = class extends NativeWorker {
      constructor(...args) {super(...args); window.testWorkers.push(this);}
    };
    const getUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia = async constraints => {
      let stream;
      try {
        let requested = constraints;
        const facing = constraints.video?.facingMode;
        const direction = typeof facing === 'string' ? facing : facing?.exact ?? facing?.ideal;
        if (emulateFacing && direction) {
          const devices = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === 'videoinput');
          const target = direction === 'environment' ? devices[1] ?? devices[0] : devices[0];
          requested = {...constraints, video: {...constraints.video, facingMode: undefined,
            deviceId: {exact: target.deviceId}}};
        }
        stream = await getUserMedia(requested);
        window.testCaptureDiagnostics.push({stage: 'getUserMedia', status: 'passed', constraints,
          settings: stream.getVideoTracks().map(t => t.getSettings())});
      } catch (error) {
        window.testCaptureDiagnostics.push({stage: 'getUserMedia', status: 'failed', name:error.name, message:error.message});
        throw error;
      }
      window.testCaptureTracks.push(...stream.getTracks());
      return stream;
    };
    const prototype = HTMLVideoElement.prototype;
    const play = prototype.play;
    prototype.play = async function(...args) {
      try {return await play.apply(this,args);}
      catch(error) {
        window.testCaptureDiagnostics.push({stage:'video.play',status:'failed',name:error.name,message:error.message});
        throw error;
      }
    };
    if (prototype.requestVideoFrameCallback) {
      const request = prototype.requestVideoFrameCallback;
      const cancel = prototype.cancelVideoFrameCallback;
      prototype.requestVideoFrameCallback = function(callback) {
        const id = request.call(this, (now, metadata) => {
          window.testFrameCallbacks.delete(id);
          callback(now, metadata);
        });
        window.testFrameCallbacks.add(id);
        return id;
      };
      prototype.cancelVideoFrameCallback = function(id) {
        window.testFrameCallbacks.delete(id);
        return cancel.call(this, id);
      };
    }
  }, emulateMobileFacing);
}

async function cameraChecks() {
  assert.equal(browserName, 'chromium', 'The Y4M webcam fixture uses Chromium flags.');
  const browser = await launch();
  const context = await browser.newContext({viewport: {width: 1280, height: 720}});
  await context.grantPermissions(['camera'], {origin: new URL(base).origin});
  const page = await context.newPage();
  observe(page);
  await installCaptureObservations(page);
  await page.goto(gallery);
  await page.getByRole('group', {name: subject.tile}).click();
  await wait(page, points => {
    const video = document.querySelector('video');
    return Number(video?.getAttribute('data-processed-frames')) >= 12 &&
      video?.getAttribute('data-landmarks') === points;
  }, subject.points);
  report.camera = await page.locator('video').evaluate(video => ({
    width: video.videoWidth, height: video.videoHeight,
    timestamp: Number(video.getAttribute('data-timestamp')),
    frames: Number(video.getAttribute('data-processed-frames')),
    mirror: video.style.transform,
  }));
  assert.equal(report.camera.width, 640);
  assert.equal(report.camera.height, 480);
  assert.equal(report.camera.mirror, 'scaleX(-1)');
  await page.screenshot({path: path.join(evidence, 'camera-' + taskName + '.png')});
  const alignment = report.alignment = await alignmentCheck(page);
  const verdict = `median ${alignment.median?.toFixed(4)}, max ${alignment.maximum?.toFixed(4)}; ` +
    `the mirrored hypothesis scores ${alignment.median_if_mirrored?.toFixed(4)}`;
  assert.equal(alignment.observed_subjects, 1, 'the on-screen preview must show one ' + taskName);
  assert.ok(alignment.median <= alignmentTolerance, 'overlay is off the on-screen ' + taskName + ': ' + verdict);
  assert.ok(alignment.maximum <= alignmentOutlierTolerance, 'one probe is far off the on-screen ' + taskName + ': ' + verdict);
  report.checks.push('overlay-alignment-oracle-on-screen-pixels');
  await wait(page, () => document.querySelector('video')?.getAttribute('data-subjects') === '0');
  await wait(page, points => document.querySelector('video')?.getAttribute('data-landmarks') === points, subject.points);
  assert.ok(await page.locator('video').evaluate(v => Number(v.getAttribute('data-timestamp'))) > report.camera.timestamp);
  report.checks.push('real-getusermedia-y4m-' + taskName + '-blank-recovery-timestamps');

  for (const viewport of [{width: 390, height: 844}, {width: 1440, height: 900}]) {
    await page.setViewportSize(viewport);
    await page.waitForFunction(() => {
      const rect = document.querySelector('video')?.getBoundingClientRect();
      return rect && Math.abs(rect.width / rect.height - 4 / 3) < 0.01;
    });
    await page.screenshot({path: path.join(evidence, 'camera-' + viewport.width + '.png')});
  }
  report.checks.push('portrait-and-landscape-preview-aspect-ratio');
  // Switch the actual running gallery task, ensuring the requested delegate
  // completes inference and releases its worker before switching back.
  await page.getByRole('button', {name: 'GPU', exact: true}).click({timeout: 30000});
  await wait(page, points => document.querySelector('video')?.getAttribute('data-delegate') === 'gpu' &&
    document.querySelector('video')?.getAttribute('data-landmarks') === points, subject.points);
  await page.screenshot({path: path.join(evidence, 'camera-gpu-' + taskName + '.png')});
  await page.getByRole('button', {name: 'CPU', exact: true}).click({timeout: 30000});
  await wait(page, points => document.querySelector('video')?.getAttribute('data-delegate') === 'cpu' &&
    document.querySelector('video')?.getAttribute('data-landmarks') === points, subject.points);
  assert.equal(await page.evaluate(() => mediapipeVision.stats().activeWorkers), 1);
  report.checks.push('live-cpu-gpu-cpu-switch-' + taskName + '-inference-worker-cleanup');
  await page.getByRole('button', {name: 'Back', exact: true}).click();
  await wait(page, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended') &&
    window.testFrameCallbacks.size === 0);
  await page.getByRole('group', {name: subject.tile}).click();
  await wait(page, points => document.querySelector('video')?.getAttribute('data-landmarks') === points, subject.points);
  await page.getByRole('button', {name: 'Back', exact: true}).click();
  await wait(page, () => mediapipeVision.stats().activeWorkers === 0 &&
    mediapipeVision.stats().pendingRequests === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended') &&
    window.testFrameCallbacks.size === 0);
  report.checks.push('automatic-start-navigation-tracks-workers-callback-cleanup');
  await context.close();
  // The checks below exercise the shared controller's lifecycle (permissions,
  // device switching, worker failure), which does not depend on the task.
  // They run once, with face.
  if (taskName !== 'face') {
    await browser.close();
    return;
  }

  const denied = await browser.newContext();
  await denied.grantPermissions([], {origin: new URL(base).origin});
  const deniedPage = await denied.newPage();
  observe(deniedPage);
  await deniedPage.goto(gallery);
  await deniedPage.getByRole('group', {name: /Live Face Landmarker/}).click();
  await deniedPage.getByText(/Camera permission denied/).waitFor();
  await wait(deniedPage, () => mediapipeVision.stats().activeWorkers === 0);
  await deniedPage.screenshot({path: path.join(evidence, 'permission-denied.png')});
  report.checks.push('browser-permission-denied-and-worker-cleanup');
  await denied.close();
  await browser.close();

  // File-backed Chrome capture exposes one device. Use Chrome's built-in
  // pattern cameras for native enumeration/device-selection coverage.
  const multiple = await launch(2, false);
  const multipleContext = await multiple.newContext({
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/153.0 Mobile/15E148 Safari/604.1',
  });
  await multipleContext.grantPermissions(['camera'], {origin: new URL(base).origin});
  const multiplePage = await multipleContext.newPage();
  observe(multiplePage);
  await installCaptureObservations(multiplePage, true);
  await multiplePage.goto(gallery);
  await multiplePage.getByRole('group', {name: /Live Face Landmarker/}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 12);
  const firstDevice = await multiplePage.evaluate(() => window.testCaptureTracks.at(-1).getSettings().deviceId);
  await multiplePage.getByRole('button', {name: 'Switch to back camera'}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 12 &&
    document.querySelector('video')?.style.transform === '');
  const secondDevice = await multiplePage.evaluate(() => window.testCaptureTracks.at(-1).getSettings().deviceId);
  assert.notEqual(firstDevice, secondDevice);
  assert.ok(await multiplePage.evaluate(() => window.testCaptureTracks.some(t => t.readyState === 'ended')));
  await multiplePage.getByRole('button', {name: 'Switch to front camera'}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 12 &&
    document.querySelector('video')?.style.transform === 'scaleX(-1)');
  const thirdDevice = await multiplePage.evaluate(() => window.testCaptureTracks.at(-1).getSettings().deviceId);
  assert.equal(thirdDevice, firstDevice);
  await multiplePage.getByRole('button', {name: 'Back', exact: true}).click();
  await wait(multiplePage, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended'));
  report.checks.push('mobile-browser-front-back-front-switch-and-mirroring');
  // Trigger the actual worker error handler while gallery capture is active.
  await multiplePage.getByRole('group', {name: /Live Face Landmarker/}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 3);
  await multiplePage.waitForFunction(() => {
    if (mediapipeVision.stats().pendingRequests === 0) return false;
    window.testWorkers.at(-1).dispatchEvent(new ErrorEvent('error', {message: 'Injected worker failure'}));
    return true;
  }, null, {polling: 1});
  await multiplePage.getByText(/Injected worker failure/).waitFor();
  await wait(multiplePage, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended'));
  report.checks.push('worker-error-rejects-pending-requests-and-releases-capture');
  await multiplePage.getByRole('button', {name: 'Back', exact: true}).click();
  await multiplePage.getByRole('group', {name: /Live Face Landmarker/}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 3);
  await multiplePage.evaluate(() => {
    window.testCaptureTracks.find(t => t.readyState === 'live').dispatchEvent(new Event('ended'));
  });
  await multiplePage.getByText(/Camera disconnected/).waitFor();
  await wait(multiplePage, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended'));
  report.checks.push('worker-error-reopen-and-simulated-track-ended-cleanup');
  await multiple.close();

  const missing = await launch(0, false);
  const missingContext = await missing.newContext();
  await missingContext.grantPermissions(['camera'], {origin: new URL(base).origin});
  const missingPage = await missingContext.newPage();
  observe(missingPage);
  await missingPage.goto(gallery);
  await missingPage.getByRole('group', {name: /Live Face Landmarker/}).click();
  await missingPage.getByText(/No camera found/).waitFor();
  await wait(missingPage, () => mediapipeVision.stats().activeWorkers === 0);
  report.checks.push('browser-no-video-device-and-worker-cleanup');
  await missing.close();
}

try {
  if (suite === 'all' || suite === 'api') await apiChecks();
  if ((suite === 'all' || suite === 'api') && browserName === 'chromium' && delegate === 'CPU') {
    await iosUserAgentCpuCheck();
  }
  if (suite === 'all' || suite === 'camera') await cameraChecks();
  assert.equal(logs.filter(entry => entry.type === 'pageerror').length, 0, JSON.stringify(logs));
  report.status = 'passed';
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  report.status = 'failed';
  report.error = error.stack;
  console.error(error);
  process.exitCode = 1;
} finally {
  for (const browser of browsers) {
    for (const context of browser.contexts()) {
      for (const page of context.pages()) {
        try {
          fs.writeFileSync(path.join(evidence, 'failure-page.html'), await page.content());
          fs.writeFileSync(path.join(evidence, 'capture-diagnostics.json'), JSON.stringify(await page.evaluate(() => ({
            capture:window.testCaptureDiagnostics,
            video: (() => {const v=document.querySelector('video'); return v ? {
              width:v.videoWidth,height:v.videoHeight,readyState:v.readyState,frames:v.getAttribute('data-processed-frames'),
              mediaError:v.error?.message,
            }: null;})(),
          })),null,2));
          await page.screenshot({path: path.join(evidence, 'failure.png')});
        } catch (_) {}
      }
    }
    await browser.close();
  }
  fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(evidence, 'browser-log.json'), JSON.stringify(logs, null, 2));
}
