// Measures the gallery's live web Face Landmarker pipeline, frame by frame,
// from the camera frame reaching the page to the browser frame after Flutter
// painted its result. Runs the release build in gallery/build/web (built with
// the trace support in gallery/lib/web/pipeline_trace.dart) in the installed
// Google Chrome, headed so WebGL uses the real GPU, with Chrome's fake camera
// playing a 30 fps 640x480 clip of the test portrait.
//
//   node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-live-pipeline/run.mjs --label=baseline
//
// Options: --label=NAME (required), --blocks=CPU,GPU,GPU,CPU (order),
// --rounds=2 (repeats of that order), --frames=1000 (timed per block),
// --warmup=1000 (frames discarded after each delegate switch, so clocks and
// the runtime settle). The window opens at the main display's origin, so every
// run paints at that display's refresh rate (recorded as `refresh`); a
// ProMotion display would switch between 60 and 120 Hz with the page's load.
// --screenshot saves the preview with its overlay next to the result.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../../../..');
const {chromium} = await import(pathToFileURL(
  path.join(repo, 'gallery/tool/browser/node_modules/playwright/index.mjs')).href);

const options = Object.fromEntries(process.argv.slice(2).map(argument => {
  const [key, value] = argument.replace(/^--/, '').split('=');
  return [key, value ?? 'true'];
}));
if (!options.label) throw new Error('Pass --label=NAME for the result file.');
const order = (options.blocks ?? 'CPU,GPU,GPU,CPU').split(',');
const rounds = Number(options.rounds ?? 2);
const timedFrames = Number(options.frames ?? 1000);
const warmup = Number(options.warmup ?? 1000);
const bundle = path.join(repo, 'gallery/build/web');
if (!fs.existsSync(path.join(bundle, 'main.dart.js'))) {
  throw new Error('Build the gallery first: flutter build web --release --base-href /mediapipe_flutter/');
}

// 30 fps camera: the portrait drifting on a slow ellipse, 90 frames, looped.
const camera = path.join(repo, 'build/bench/web-camera-30fps.y4m');
if (!fs.existsSync(camera)) {
  fs.mkdirSync(path.dirname(camera), {recursive: true});
  const portrait = path.join(repo, 'packages/mediapipe-task-vision/test/fixtures/face_detection/landmark-ex1.jpg');
  execFileSync('ffmpeg', ['-n', '-hide_banner', '-loglevel', 'error',
    '-loop', '1', '-framerate', '30', '-t', '3', '-i', portrait,
    '-vf', 'scale=704:528:force_original_aspect_ratio=decrease,pad=704:528:(ow-iw)/2:(oh-ih)/2,' +
      "crop=640:480:x='32+24*sin(2*PI*n/90)':y='24+16*cos(2*PI*n/90)',format=yuv420p,setsar=1",
    '-r', '30', '-pix_fmt', 'yuv420p', camera]);
}

const types = {'.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.otf': 'font/otf', '.ttf': 'font/ttf'};
const server = http.createServer((request, response) => {
  const prefix = '/mediapipe_flutter/';
  let name = decodeURIComponent(new URL(request.url, 'http://x').pathname);
  if (!name.startsWith(prefix)) return response.writeHead(404).end();
  name = name.slice(prefix.length) || 'index.html';
  const file = path.join(bundle, name);
  if (!file.startsWith(bundle) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    return response.writeHead(404).end();
  }
  response.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream'});
  fs.createReadStream(file).pipe(response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/mediapipe_flutter/`;

const quantile = (values, q) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const at = (sorted.length - 1) * q, low = Math.floor(at);
  return sorted[low] + (sorted[Math.ceil(at)] - sorted[low]) * (at - low);
};
// Stage durations in milliseconds for one frame, given its worker timing.
function stages(frame, worker, origin) {
  const toMain = absolute => absolute - origin;
  return {
    e2e: frame.painted - frame.arrived,
    queue: frame.started - frame.arrived,
    bitmap: frame.bitmap - frame.started,
    roundTrip: frame.detected - frame.bitmap,
    toWorker: worker ? toMain(worker.received) - frame.bitmap : null,
    inference: worker?.inference ?? null,
    serialize: worker?.serialize ?? null,
    fromWorker: worker ? frame.detected - toMain(worker.sent) : null,
    waitFrame: frame.frame - frame.detected,
    render: frame.built - frame.frame,
    present: frame.painted - frame.built,
    // One display refresh: from the painting frame's vsync to the next.
    refresh: frame.painted - frame.frame,
    ...(frame.captured == null ? {} : {sinceCapture: frame.painted - frame.captured}),
  };
}
const keys = ['e2e', 'queue', 'bitmap', 'roundTrip', 'toWorker', 'inference', 'serialize',
  'fromWorker', 'waitFrame', 'render', 'present', 'refresh', 'sinceCapture'];
function summarize(rows) {
  const summary = {};
  for (const key of keys) {
    const values = rows.map(row => row[key]).filter(value => value != null);
    if (values.length) {
      summary[key] = {median: quantile(values, 0.5), mean: values.reduce((a, b) => a + b) / values.length,
        p90: quantile(values, 0.9)};
    }
  }
  return summary;
}

const browser = await chromium.launch({channel: 'chrome', headless: false, args: [
  '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
  `--use-file-for-fake-video-capture=${camera}`,
  // Keep timers and rendering at full rate if the window is covered.
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows', '--window-position=0,0',
]});
try {
  const context = await browser.newContext({viewport: {width: 1280, height: 720}});
  await context.grantPermissions(['camera'], {origin: new URL(base).origin});
  const page = await context.newPage();
  page.on('pageerror', error => console.log(`[page error] ${error.message}`));
  await page.goto(`${base}?pipeline-trace`);
  await page.bringToFront();
  await page.getByRole('group', {name: /Live Face Landmarker/}).click();
  // The bridge loads with the first task; its timings before this are warm-up.
  await page.waitForFunction(() => globalThis.mediapipeVision && typeof __pipelineTrace === 'function',
    null, {timeout: 60000});
  await page.evaluate(() => {
    window.__workerTimings = [];
    mediapipeVision.onTiming = timing => window.__workerTimings.push(timing);
  });
  const origin = await page.evaluate(() => performance.timeOrigin);
  const drain = () => page.evaluate(() => {
    const workers = window.__workerTimings;
    window.__workerTimings = [];
    return {frames: JSON.parse(__pipelineTrace()), workers};
  });

  const blocks = [];
  for (let round = 0; round < rounds; round++) {
    for (const delegate of order) {
      await page.getByRole('button', {name: delegate, exact: true}).click({timeout: 30000});
      // Wait for the restarted task's frames, then discard the warm-up.
      for (let deadline = Date.now() + 60000; ;) {
        const {frames} = await drain();
        if (frames.some(frame => frame.delegate === delegate.toLowerCase())) break;
        if (Date.now() > deadline) throw new Error(`No ${delegate} frames after switching`);
        await page.waitForTimeout(250);
      }
      // Collect until enough frames of this delegate; returns them with the
      // worker timings and the wall time taken.
      const collect = async count => {
        const frames = [], workers = [], started = Date.now();
        while (frames.length < count) {
          await page.waitForTimeout(1000);
          const next = await drain();
          frames.push(...next.frames.filter(frame => frame.delegate === delegate.toLowerCase()));
          workers.push(...next.workers);
        }
        return {frames: frames.slice(0, count), workers, seconds: (Date.now() - started) / 1000};
      };
      await collect(warmup);
      const {frames: measured, workers, seconds} = await collect(timedFrames);
      const byTimestamp = new Map(workers.map(worker => [worker.timestamp, worker]));
      const rows = measured.map(frame => stages(frame, byTimestamp.get(frame.timestamp), origin));
      const block = {round, delegate, frames: measured.length,
        fps: measured.length / seconds,
        seconds,
        faceFrames: measured.filter(frame => frame.faces > 0).length,
        summary: summarize(rows), rows};
      blocks.push(block);
      console.log(`${delegate} round ${round + 1}: ${measured.length} frames, ` +
        `e2e median ${block.summary.e2e.median.toFixed(2)} ms, ` +
        `inference ${block.summary.inference?.median.toFixed(2)} ms`);
    }
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  if (options.screenshot) {
    await page.locator('video').screenshot({path: path.join(here, 'results', `${options.label}-${stamp}.png`)});
  }
  const git = (...args) => execFileSync('git', args, {cwd: repo}).toString().trim();
  const result = {
    label: options.label,
    settings: {order, rounds, timedFrames, warmup, camera: '640x480 at 30 fps (Chrome fake device, Y4M)'},
    environment: {
      startedAt: new Date().toISOString(),
      commit: git('rev-parse', '--short', 'HEAD'),
      dirty: git('status', '--porcelain', '--untracked-files=no') !== '',
      browser: `Chrome ${browser.version()}`,
      host: {platform: `${os.platform()} ${os.release()}`, cpu: os.cpus()[0]?.model},
    },
    pooled: Object.fromEntries(['CPU', 'GPU'].filter(d => order.includes(d)).map(delegate => [delegate,
      summarize(blocks.filter(block => block.delegate === delegate).flatMap(block => block.rows))])),
    blocks,
  };
  const out = path.join(here, 'results',
    `${options.label}-${stamp}.json`);
  fs.mkdirSync(path.dirname(out), {recursive: true});
  fs.writeFileSync(out, JSON.stringify(result) + '\n');

  console.log(`\n${options.label} (${result.environment.commit}${result.environment.dirty ? ', dirty' : ''}), ` +
    `${result.environment.browser}: pooled median/mean ms`);
  for (const [delegate, summary] of Object.entries(result.pooled)) {
    console.log(`  ${delegate}: ` + keys.filter(key => summary[key])
      .map(key => `${key} ${summary[key].median.toFixed(2)}/${summary[key].mean.toFixed(2)}`).join(', '));
    console.log(`       block e2e means: ` + blocks.filter(block => block.delegate === delegate)
      .map(block => block.summary.e2e.mean.toFixed(2)).join(', ') +
      `; fps ` + blocks.filter(block => block.delegate === delegate).map(block => block.fps.toFixed(1)).join(', '));
  }
  console.log(`\nSaved ${path.relative(repo, out)}`);
} finally {
  await browser.close();
  server.close();
}
