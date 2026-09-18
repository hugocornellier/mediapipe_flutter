import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, firefox} from 'playwright';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const argumentsMap = Object.fromEntries(process.argv.slice(2).map(arg => arg.replace(/^--/, '').split('=')));
const browserName = argumentsMap.browser || 'chromium';
const suite = argumentsMap.suite || 'all';
const base = argumentsMap['base-url'] || 'http://localhost:8866/mediapipe_flutter/';
const apiBase = argumentsMap['api-url'] || 'http://localhost:8866/api-probe/';
const evidence = path.join(repo, 'build/codex-tmp/web-browser-' + browserName);
fs.mkdirSync(evidence, {recursive: true});
const report = {browser: browserName, suite, checks: [], physical_webcam_tested: false};
const logs = [];
const browsers = [];

async function launch(deviceCount = 2, useFile = true) {
  const localChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const options = browserName === 'chromium' ? {
    executablePath: process.platform === 'darwin' && fs.existsSync(localChrome) ? localChrome : undefined,
    args: ['--use-fake-device-for-media-stream=device-count=' + deviceCount,
      ...(useFile ? ['--use-file-for-fake-video-capture=' + path.join(repo, 'build/codex-tmp/web-camera.y4m')] : [])],
  } : {};
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

async function wait(page, condition, timeout = 60000) {
  await page.waitForFunction(condition, null, {timeout});
}

async function apiChecks() {
  const browser = await launch();
  const page = await browser.newPage();
  observe(page);
  await page.goto(apiBase);
  await wait(page, () => window.mediapipeApiTestReport);
  const api = await page.evaluate(() => window.mediapipeApiTestReport);
  fs.writeFileSync(path.join(evidence, 'api-report.json'), JSON.stringify(api, null, 2));
  assert.equal(api.status, 'passed', JSON.stringify(api));
  const direct = await page.evaluate(async () => {
    const runtime = new URL('assets/packages/mediapipe_flutter_vision_web/assets/runtime/', document.baseURI);
    const {FilesetResolver, FaceLandmarker} = await import(new URL('vision_bundle.mjs', runtime));
    const files = await FilesetResolver.forVisionTasks(new URL('wasm', runtime).href);
    const task = await FaceLandmarker.createFromOptions(files, {
      baseOptions: {delegate: 'CPU', modelAssetPath: new URL('assets/assets/models/face_landmarker.task', document.baseURI).href},
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
  });
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
  assert.deepEqual(await page.evaluate(() => mediapipeVision.stats().activeWorkers), 0);
  report.official_js_maximum_absolute_error = errors;
  report.checks.push(...api.checks, 'same-browser-official-js-reference');
  await page.screenshot({path: path.join(evidence, 'api.png')});
  await browser.close();
}

async function installCaptureObservations(page) {
  await page.addInitScript(() => {
    window.testCaptureTracks = [];
    window.testFrameCallbacks = new Set();
    const getUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia = async constraints => {
      const stream = await getUserMedia(constraints);
      window.testCaptureTracks.push(...stream.getTracks());
      return stream;
    };
    const prototype = HTMLVideoElement.prototype;
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
  });
}

async function cameraChecks() {
  assert.equal(browserName, 'chromium', 'The Y4M webcam fixture uses Chromium flags.');
  const browser = await launch();
  const context = await browser.newContext({viewport: {width: 1280, height: 720}});
  await context.grantPermissions(['camera'], {origin: new URL(base).origin});
  const page = await context.newPage();
  observe(page);
  await installCaptureObservations(page);
  await page.goto(base);
  await page.getByRole('group', {name: /Live Face Mesh/}).click();
  await wait(page, () => {
    const video = document.querySelector('video');
    return Number(video?.getAttribute('data-processed-frames')) >= 12 &&
      video?.getAttribute('data-landmarks') === '478';
  });
  report.camera = await page.locator('video').evaluate(video => ({
    width: video.videoWidth, height: video.videoHeight,
    timestamp: Number(video.getAttribute('data-timestamp')),
    frames: Number(video.getAttribute('data-processed-frames')),
    mirror: video.style.transform,
  }));
  assert.equal(report.camera.width, 640);
  assert.equal(report.camera.height, 480);
  assert.equal(report.camera.mirror, 'scaleX(-1)');
  await page.screenshot({path: path.join(evidence, 'camera-face.png')});
  await wait(page, () => document.querySelector('video')?.getAttribute('data-face-count') === '0');
  await wait(page, () => document.querySelector('video')?.getAttribute('data-landmarks') === '478');
  assert.ok(await page.locator('video').evaluate(v => Number(v.getAttribute('data-timestamp'))) > report.camera.timestamp);
  report.checks.push('real-getusermedia-y4m-face-blank-recovery-timestamps');

  for (const viewport of [{width: 390, height: 844}, {width: 1440, height: 900}]) {
    await page.setViewportSize(viewport);
    await page.waitForFunction(() => {
      const rect = document.querySelector('video')?.getBoundingClientRect();
      return rect && Math.abs(rect.width / rect.height - 4 / 3) < 0.01;
    });
    await page.screenshot({path: path.join(evidence, 'camera-' + viewport.width + '.png')});
  }
  report.checks.push('portrait-and-landscape-preview-aspect-ratio');
  await page.getByRole('button', {name: 'Stop camera'}).click();
  await wait(page, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended') &&
    window.testFrameCallbacks.size === 0);
  await page.getByRole('button', {name: 'Start camera'}).click();
  await wait(page, () => document.querySelector('video')?.getAttribute('data-landmarks') === '478');
  await page.getByRole('button', {name: 'Back', exact: true}).click();
  await wait(page, () => mediapipeVision.stats().activeWorkers === 0 &&
    mediapipeVision.stats().pendingRequests === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended') &&
    window.testFrameCallbacks.size === 0);
  report.checks.push('stop-restart-navigation-tracks-workers-callback-cleanup');
  await context.close();

  const denied = await browser.newContext();
  await denied.grantPermissions([], {origin: new URL(base).origin});
  const deniedPage = await denied.newPage();
  observe(deniedPage);
  await deniedPage.goto(base);
  await deniedPage.getByRole('group', {name: /Live Face Mesh/}).click();
  await deniedPage.getByText(/Camera permission denied/).waitFor();
  await wait(deniedPage, () => mediapipeVision.stats().activeWorkers === 0);
  await deniedPage.screenshot({path: path.join(evidence, 'permission-denied.png')});
  report.checks.push('browser-permission-denied-and-worker-cleanup');
  await denied.close();
  await browser.close();

  // File-backed Chrome capture exposes one device. Use Chrome's built-in
  // pattern cameras for native enumeration/device-selection coverage.
  const multiple = await launch(2, false);
  const multipleContext = await multiple.newContext();
  await multipleContext.grantPermissions(['camera'], {origin: new URL(base).origin});
  const multiplePage = await multipleContext.newPage();
  observe(multiplePage);
  await installCaptureObservations(multiplePage);
  await multiplePage.goto(base);
  await multiplePage.getByRole('group', {name: /Live Face Mesh/}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 12);
  const firstDevice = await multiplePage.evaluate(() => window.testCaptureTracks.at(-1).getSettings().deviceId);
  await multiplePage.getByRole('button', {name: 'Switch to back camera'}).click();
  await wait(multiplePage, () => Number(document.querySelector('video')?.getAttribute('data-processed-frames')) >= 12 &&
    document.querySelector('video')?.style.transform === '');
  const secondDevice = await multiplePage.evaluate(() => window.testCaptureTracks.at(-1).getSettings().deviceId);
  assert.notEqual(firstDevice, secondDevice);
  assert.ok(await multiplePage.evaluate(() => window.testCaptureTracks.some(t => t.readyState === 'ended')));
  await multiplePage.getByRole('button', {name: 'Back', exact: true}).click();
  await wait(multiplePage, () => mediapipeVision.stats().activeWorkers === 0 &&
    window.testCaptureTracks.every(t => t.readyState === 'ended'));
  report.checks.push('native-browser-device-switch-and-mirroring');
  await multiple.close();

  const missing = await launch(0, false);
  const missingContext = await missing.newContext();
  await missingContext.grantPermissions(['camera'], {origin: new URL(base).origin});
  const missingPage = await missingContext.newPage();
  observe(missingPage);
  await missingPage.goto(base);
  await missingPage.getByRole('group', {name: /Live Face Mesh/}).click();
  await missingPage.getByText(/No camera found/).waitFor();
  await wait(missingPage, () => mediapipeVision.stats().activeWorkers === 0);
  report.checks.push('browser-no-video-device-and-worker-cleanup');
  await missing.close();
}

try {
  if (suite === 'all' || suite === 'api') await apiChecks();
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
          await page.screenshot({path: path.join(evidence, 'failure.png')});
        } catch (_) {}
      }
    }
    await browser.close();
  }
  fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(evidence, 'browser-log.json'), JSON.stringify(logs, null, 2));
}
