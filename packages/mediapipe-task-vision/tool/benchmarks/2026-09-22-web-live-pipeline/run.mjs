// Measures the gallery's live web Face Landmarker pipeline, frame by frame,
// from the camera frame reaching the page to the browser frame after Flutter
// painted its result. Runs release builds of the gallery (with the trace in
// gallery/lib/web/pipeline_trace.dart) in the installed Google Chrome, headed
// so WebGL uses the real GPU, with Chrome's fake camera playing a 30 fps
// 640x480 clip of the test portrait.
//
//   node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-live-pipeline/run.mjs --label=NAME \
//     --variants=before=build/bench/variants/before,after=build/bench/variants/after
//
// Machine speed drifts by a few tenths of a millisecond over an hour, so
// compare builds within one run: with two or more --variants (name=bundle,
// paths relative to the repository; default: the current gallery/build/web),
// each round runs every delegate as A, B, B, A (reversed on odd rounds), each
// block in a freshly loaded page.
//
// Options: --label=NAME (required), --delegates=CPU,GPU, --rounds=2,
// --frames=1000 (timed per block), --warmup=1000 (frames discarded first, so
// clocks and the runtime settle), --isolated (serve cross-origin isolated, so
// performance.now() resolves to about 5 us instead of 100 us; compare only runs
// made in the same mode), --screenshot (save each variant's last preview).
// The window opens at the main display's origin, so every block paints at that
// display's refresh rate (recorded as `refresh`).
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
  const [key, ...value] = argument.replace(/^--/, '').split('=');
  return [key, value.length ? value.join('=') : 'true'];
}));
if (!options.label) throw new Error('Pass --label=NAME for the result file.');
const delegates = (options.delegates ?? 'CPU,GPU').split(',');
const rounds = Number(options.rounds ?? 2);
const timedFrames = Number(options.frames ?? 1000);
const warmup = Number(options.warmup ?? 1000);
const isolated = Boolean(options.isolated);
const variants = (options.variants ?? 'current=gallery/build/web').split(',').map(entry => {
  const [name, bundle] = entry.split('=');
  const root = path.resolve(repo, bundle);
  if (!fs.existsSync(path.join(root, 'main.dart.js'))) throw new Error(`No web build at ${root}`);
  return {name, root};
});

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

// One loopback server per variant, each at /mediapipe_flutter/ (the base href).
const types = {'.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.otf': 'font/otf', '.ttf': 'font/ttf'};
const servers = [];
for (const variant of variants) {
  const server = http.createServer((request, response) => {
    const prefix = '/mediapipe_flutter/';
    let name = decodeURIComponent(new URL(request.url, 'http://x').pathname);
    if (!name.startsWith(prefix)) return response.writeHead(404).end();
    name = name.slice(prefix.length) || 'index.html';
    const file = path.join(variant.root, name);
    if (!file.startsWith(variant.root) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      return response.writeHead(404).end();
    }
    response.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream',
      ...(isolated ? {'cross-origin-opener-policy': 'same-origin',
        'cross-origin-embedder-policy': 'require-corp'} : {})});
    fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  servers.push(server);
  variant.base = `http://127.0.0.1:${server.address().port}/mediapipe_flutter/`;
}

const quantile = (values, q) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const at = (sorted.length - 1) * q, low = Math.floor(at);
  return sorted[low] + (sorted[Math.ceil(at)] - sorted[low]) * (at - low);
};
const mean = values => values.reduce((a, b) => a + b, 0) / values.length;
// Stage durations in milliseconds for one frame, given its worker timing.
// Page and worker clocks disagree by up to about 0.5 ms, so toWorker and
// fromWorker are indicative; transport (round trip less the worker's own
// work) does not depend on them.
function stages(frame, worker, origin) {
  const toMain = absolute => absolute - origin;
  return {
    e2e: frame.painted - frame.arrived,
    queue: frame.started - frame.arrived,
    capture: frame.bitmap - frame.started,
    roundTrip: frame.detected - frame.bitmap,
    detectDone: frame.detected - frame.arrived,
    inference: worker?.inference ?? null,
    serialize: worker?.serialize ?? null,
    transport: worker ? frame.detected - frame.bitmap - worker.inference - worker.serialize : null,
    toWorker: worker ? toMain(worker.received) - frame.bitmap : null,
    fromWorker: worker ? frame.detected - toMain(worker.sent) : null,
    waitFrame: frame.frame - frame.detected,
    render: frame.built - frame.frame,
    present: frame.painted - frame.built,
    // One display refresh: from the painting frame's vsync to the next.
    refresh: frame.painted - frame.frame,
    ...(frame.captured == null ? {} : {sinceCapture: frame.painted - frame.captured}),
  };
}
const keys = ['e2e', 'queue', 'capture', 'roundTrip', 'detectDone', 'inference', 'serialize', 'transport',
  'toWorker', 'fromWorker', 'waitFrame', 'render', 'present', 'refresh', 'sinceCapture'];
const shown = ['e2e', 'detectDone', 'capture', 'inference', 'transport', 'render'];
function summarize(rows) {
  const summary = {};
  for (const key of keys) {
    const values = rows.map(row => row[key]).filter(value => value != null);
    if (values.length) {
      summary[key] = {median: quantile(values, 0.5), mean: mean(values), p90: quantile(values, 0.9)};
    }
  }
  return summary;
}

// The block order: per round and delegate, the variants then their reverse
// (A, B, B, A), flipped on odd rounds; one variant runs twice per delegate.
const schedule = [];
for (let round = 0; round < rounds; round++) {
  const names = round % 2 ? [...variants].reverse() : variants;
  for (const delegate of delegates) {
    for (const variant of [...names, ...[...names].reverse()]) schedule.push({round, delegate, variant});
  }
}

const browser = await chromium.launch({channel: 'chrome', headless: false, args: [
  '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
  `--use-file-for-fake-video-capture=${camera}`,
  // Keep timers and rendering at full rate if the window is covered.
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows', '--window-position=0,0',
]});
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
try {
  const context = await browser.newContext({viewport: {width: 1280, height: 720}});
  for (const variant of variants) await context.grantPermissions(['camera'], {origin: new URL(variant.base).origin});

  // One block: a fresh page on the variant, the delegate selected, warm-up
  // frames discarded, then the timed frames.
  async function runBlock({round, delegate, variant}, last) {
    const page = await context.newPage();
    page.on('pageerror', error => console.log(`[page error] ${error.message}`));
    try {
      await page.goto(`${variant.base}?pipeline-trace`);
      await page.bringToFront();
      await page.getByRole('group', {name: /Live Face Landmarker/}).click();
      await page.waitForFunction(() => globalThis.mediapipeVision && typeof __pipelineTrace === 'function',
        null, {timeout: 60000});
      await page.evaluate(() => {
        window.__workerTimings = [];
        mediapipeVision.onTiming = timing => window.__workerTimings.push(timing);
      });
      if (await page.evaluate(() => crossOriginIsolated) !== isolated) {
        throw new Error(`crossOriginIsolated is not ${isolated}`);
      }
      const origin = await page.evaluate(() => performance.timeOrigin);
      const drain = () => page.evaluate(() => {
        const workers = window.__workerTimings;
        window.__workerTimings = [];
        return {frames: JSON.parse(__pipelineTrace()), workers};
      });
      await page.getByRole('button', {name: delegate, exact: true}).click({timeout: 30000});
      const wanted = delegate.toLowerCase();
      const collect = async count => {
        const frames = [], workers = [], started = Date.now();
        while (frames.length < count) {
          if (Date.now() - started > 60000 + count * 100) throw new Error(`Too few ${delegate} frames`);
          await page.waitForTimeout(1000);
          const next = await drain();
          frames.push(...next.frames.filter(frame => frame.delegate === wanted));
          workers.push(...next.workers);
        }
        return {frames: frames.slice(0, count), workers, seconds: (Date.now() - started) / 1000};
      };
      await collect(warmup);
      const {frames, workers, seconds} = await collect(timedFrames);
      const byTimestamp = new Map(workers.map(worker => [worker.timestamp, worker]));
      const rows = frames.map(frame => stages(frame, byTimestamp.get(frame.timestamp), origin));
      if (options.screenshot && last) {
        await page.locator('video').screenshot({path: path.join(here, 'results', `${options.label}-${variant.name}-${stamp}.png`)});
      }
      return {round, delegate, variant: variant.name, frames: frames.length, seconds,
        faceFrames: frames.filter(frame => frame.faces > 0).length, summary: summarize(rows), rows};
    } finally {
      await page.close();
    }
  }

  const blocks = [];
  for (const [index, entry] of schedule.entries()) {
    const last = !schedule.slice(index + 1).some(next => next.variant === entry.variant);
    const block = await runBlock(entry, last);
    blocks.push(block);
    console.log(`${String(index + 1).padStart(2)}/${schedule.length} ${block.variant} ${block.delegate}: ` +
      shown.map(key => `${key} ${block.summary[key]?.mean.toFixed(3)}`).join(', ') +
      `, faces ${block.faceFrames}/${block.frames}`);
  }

  const git = (...args) => execFileSync('git', args, {cwd: repo}).toString().trim();
  const result = {
    label: options.label,
    settings: {delegates, rounds, timedFrames, warmup, isolated,
      variants: variants.map(({name, root}) => ({name, bundle: path.relative(repo, root)})),
      camera: '640x480 at 30 fps (Chrome fake device, Y4M)'},
    environment: {
      startedAt: new Date().toISOString(),
      commit: git('rev-parse', '--short', 'HEAD'),
      dirty: git('status', '--porcelain', '--untracked-files=no') !== '',
      browser: `Chrome ${browser.version()}`,
      host: {platform: `${os.platform()} ${os.release()}`, cpu: os.cpus()[0]?.model},
    },
    pooled: {},
    blocks,
  };
  for (const variant of variants) {
    for (const delegate of delegates) {
      result.pooled[`${variant.name} ${delegate}`] = summarize(blocks
        .filter(block => block.variant === variant.name && block.delegate === delegate).flatMap(block => block.rows));
    }
  }
  const out = path.join(here, 'results', `${options.label}-${stamp}.json`);
  fs.mkdirSync(path.dirname(out), {recursive: true});
  fs.writeFileSync(out, JSON.stringify(result) + '\n');

  console.log(`\n${options.label}${isolated ? ' [isolated]' : ''}, ${result.environment.browser}: ` +
    'pooled means in ms (block means in brackets)');
  for (const delegate of delegates) {
    for (const variant of variants) {
      const own = blocks.filter(block => block.variant === variant.name && block.delegate === delegate);
      const summary = result.pooled[`${variant.name} ${delegate}`];
      console.log(`  ${delegate} ${variant.name.padEnd(12)} ` + shown.map(key =>
        `${key} ${summary[key]?.mean.toFixed(3)} [${own.map(block => block.summary[key]?.mean.toFixed(3)).join(' ')}]`)
        .join(', '));
    }
  }
  console.log(`\nSaved ${path.relative(repo, out)}`);
} finally {
  await browser.close();
  for (const server of servers) server.close();
}
