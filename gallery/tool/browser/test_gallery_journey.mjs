import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, firefox, webkit} from 'playwright';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const args = Object.fromEntries(process.argv.slice(2).map(arg => arg.replace(/^--/, '').split('=')));
const browserName = args.browser || 'chromium';
const base = args['base-url'] || 'http://127.0.0.1:8866/mediapipe_flutter/';
const evidence = path.join(repo, 'build/codex-tmp/gallery-journey-' + browserName);
fs.mkdirSync(evidence, {recursive: true});

// This table describes user-facing actions, not which tasks a build contains.
// The release manifest decides that; an unknown bundled task fails the test.
const cases = {
  face_detector: {title: 'Face Detector', sample: 'portrait.jpg', result: /[1-9]\d* faces? detected/},
  face_landmarker: {title: 'Face Landmarker', sample: 'portrait.jpg', result: /[1-9]\d* faces? detected/},
  gesture_recognizer: {title: 'Gesture Recognizer', sample: 'thumb_up.jpg', result: /[1-9]\d* hands? recognized/},
  hand_landmarker: {title: 'Hand Landmarker', sample: 'hands.jpg', result: /[1-9]\d* hands? detected/},
  holistic_landmarker: {title: 'Holistic Landmarker', sample: 'pose.jpg', result: /Body landmarks detected/},
  image_classifier: {title: 'Image Classifier', sample: 'portrait.jpg', result: /[1-9]\d* classes returned/},
  image_embedder: {title: 'Image Embedder', sample: 'portrait.jpg', result: /[1-9]\d* embeddings generated/},
  image_segmenter: {title: 'Image Segmenter', sample: 'portrait.jpg', result: /Segmentation complete/},
  object_detector: {title: 'Object Detector', sample: 'group.jpeg', result: /[1-9]\d* objects? detected/},
  pose_landmarker: {title: 'Pose Landmarker', sample: 'pose.jpg', result: /[1-9]\d* poses? detected/},
  interactive_segmenter: {title: 'Interactive Segmenter', segment: true},
  audio_classifier: {title: 'Audio Classifier', audio: true},
  // A category row reads "<category> <score>"; the sample's own category
  // must score at least 0.5, not merely be listed.
  language_detector: {title: 'Language Detector', text: true, row: /^fr (0\.[5-9]|1\.0)/},
  text_classifier: {title: 'Text Classifier', text: true, row: /^positive (0\.[5-9]|1\.0)/},
  text_embedder: {title: 'Text Embedder', text: true, result: /^Cosine similarity -?\d+\.\d+$/},
};

// The delegates each page must offer and run come from the coverage matrix the
// gate enforces: a required web GPU cell that the UI stops offering fails here.
const matrix = JSON.parse(fs.readFileSync(path.join(repo, 'tool/coverage/matrix.json'), 'utf8')).cells;
const delegatesFor = id => ['cpu', 'gpu'].filter(delegate => matrix[id]?.web?.[delegate] === 'required');

const report = {browser: browserName, checks: [], tasks: [], errors: [], steps: [], events: []};
// Each step and browser event carries the wall clock, to line up with the
// browser's own logs.
let step = 'launch';
const enter = name => {
  step = name;
  report.steps.push(`${new Date().toISOString()} ${name}`);
};
// A browser that drops the page leaves Playwright reporting only that it is
// closed; these events say which part went and during which step.
let closing = false;
const lifecycle = event => {
  if (closing) return;
  const line = `${new Date().toISOString()} ${step}: ${event}`;
  report.events.push(line);
  console.log(`Journey event: ${line}`);
};
// Hosted Linux has no GPU, and Google's vision tasks need a WebGL context even
// on CPU, so allow software WebGL there as test_browser.mjs does. Each engine
// also gets a fake camera: Chromium plays the face fixture when it has been
// prepared, Firefox its synthetic stream, and WebKit its mock capture device.
const linux = process.platform === 'linux';
const fixture = path.join(repo, 'build/codex-tmp/web-camera.y4m');
const browser = await ({chromium, firefox, webkit}[browserName]).launch({
  headless: args.headed !== 'true',
  ...(browserName === 'chromium' ? {
    channel: 'chromium',
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
      ...(fs.existsSync(fixture) ? ['--use-file-for-fake-video-capture=' + fixture] : []),
      ...(linux ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : []),
    ],
  } : {}),
  ...(browserName === 'firefox' ? {firefoxUserPrefs: {
    'media.navigator.streams.fake': true,
    'media.navigator.permission.disabled': true,
    ...(linux ? {'webgl.force-enabled': true} : {}),
  }} : {}),
});
browser.on('disconnected', () => lifecycle('browser disconnected'));
let page;
try {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}});
  context.on('close', () => lifecycle('context closed'));
  try {
    await context.grantPermissions(['camera'], {origin: new URL(base).origin});
  } catch {
    // Firefox takes camera access from the preference above instead.
  }
  page = await context.newPage();
  page.on('crash', () => lifecycle('page crashed'));
  page.on('close', () => lifecycle('page closed'));
  // Each error names the step it happened in; some engines throw errors with
  // no message, so the name and the top of the stack are kept too.
  enter('load');
  page.on('pageerror', error => report.errors.push(
    `${step}: ${error.name || 'Error'}: ${error.message || '(no message)'}` +
    (error.stack ? ` | ${error.stack.split('\n').slice(0, 3).join(' / ')}` : '')));
  page.on('response', response => {
    if (response.status() >= 400) report.errors.push(`${step}: ${response.status()} ${response.url()}`);
  });
  const manifestResponse = await page.request.get(new URL('assets/assets/manifest.json', base).href);
  assert.ok(manifestResponse.ok(), 'release manifest unavailable');
  const manifest = await manifestResponse.json();
  const expected = manifest.tasks.filter(id => id !== 'interactive_segmenter_legacy');
  assert.ok(expected.length > 0, 'empty release task list');
  for (const id of expected) assert.ok(cases[id], `new bundled task ${id} needs a gallery journey`);
  // Flutter renders sidebar links as <a> without an href, which has no link
  // role, so match the item's own anchor by its exact text.
  const sidebarItem = title => page.locator('a[flt-tappable]')
    .filter({hasText: new RegExp(`^${title}$`)});
  // The sidebar marks its item current in the frame that builds the item's
  // page, so nothing after this finds a control of the previous page.
  const openedPage = title => page.locator('a[flt-tappable][aria-current="true"]')
    .filter({hasText: new RegExp(`^${title}$`)});
  // A segment of a CPU/GPU control; clicking waits until the page enables it.
  const delegateButton = delegate => page.getByRole('button', {name: delegate.toUpperCase(), exact: true});
  // The status line under a running feed reads "20.1 fps · 5 ms · GPU", with a
  // frame rate above zero once frames arrive on that delegate.
  const liveFrames = delegate =>
    page.getByText(new RegExp(`^(?!0\\.0 fps)\\d+\\.\\d fps · \\d+ ms · ${delegate.toUpperCase()}$`));
  // A still image's status line names the delegate that produced it.
  const stillRan = delegate =>
    page.getByText(new RegExp(`Inference \\d+\\.\\d ms · ${delegate.toUpperCase()}$`));
  await page.goto(base);
  await sidebarItem('Home').waitFor({timeout: 120000});

  for (const id of expected) {
    const spec = cases[id];
    enter(`${id}:open`);
    await sidebarItem(spec.title).click();
    await openedPage(spec.title).waitFor();
    if (spec.sample) {
      const delegates = delegatesFor(id);
      assert.ok(delegates.length > 0, `${id} has no required web delegate`);
      // The page opens with the camera running. Each delegate must keep frames
      // coming, and the second is reached by switching while the camera runs.
      for (const delegate of delegates) {
        enter(`${id}:${delegate}:live`);
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        await liveFrames(delegate).waitFor({timeout: 120000});
        report.checks.push(`${id}:${delegate}:live`);
      }
      await page.screenshot({path: path.join(evidence, `${id}-live.png`)});
      enter(`${id}:mode`);
      await page.getByRole('button', {name: 'Still image', exact: true}).click();
      const choose = page.getByRole('button', {name: 'Choose image'});
      await choose.waitFor();
      const chooserPromise = page.waitForEvent('filechooser');
      await choose.click();
      const chooser = await chooserPromise;
      await chooser.setFiles(path.join(repo, 'gallery/assets/samples', spec.sample));
      // The image runs on the delegate the camera ended on; switching back
      // runs it again on the other.
      for (const delegate of [...delegates].reverse()) {
        enter(`${id}:${delegate}:still`);
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        await stillRan(delegate).waitFor({timeout: 120000});
        await page.getByText(spec.result).waitFor();
        report.checks.push(`${id}:${delegate}:still`);
      }
      // The status line opens with the chosen file's name.
      assert.equal(await page.getByText(new RegExp(`^${spec.sample.replace('.', '\\.')} · `)).count(), 1);
      await page.screenshot({path: path.join(evidence, `${id}-still.png`)});
    } else if (spec.text) {
      enter(`${id}:run`);
      await page.getByRole('button', {name: id === 'text_embedder' ? 'Compare' : 'Run', exact: true}).click();
      await page.getByText(spec.row || spec.result)
        .waitFor({timeout: 120000});
      await page.getByText(/Done in \d+\.\d ms/).waitFor();
      report.checks.push(`${id}:cpu:run`);
    } else if (spec.audio) {
      enter(`${id}:run`);
      // The first window of the speech clip is heard as speech.
      await page.getByText(/^Speech \d\.\d{2}$/).first().waitFor({timeout: 120000});
      await page.getByText(/Done in \d+\.\d ms/).waitFor();
      report.checks.push(`${id}:cpu:run`);
    } else if (spec.segment) {
      const delegates = delegatesFor(id);
      assert.ok(delegates.length > 0, `${id} has no required web delegate`);
      for (const delegate of delegates) {
        enter(`${id}:${delegate}:tap`);
        // Switching reopens the task, so the image is tapped again after it.
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        // Wait for the newly opened delegate's canvas before clicking. The
        // old canvas can still be visible when the delegate click returns.
        // Use real pointer events; a semantics tap has no position.
        const image = page.locator(`[flt-semantics-identifier="segment-canvas-${delegate}"]`);
        await image.waitFor({timeout: 120000});
        const box = await image.boundingBox();
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
        await page.getByText(new RegExp(
          `\\d+\\.\\d ms · \\d+ requests · \\d+ coalesced · ${delegate.toUpperCase()}$`,
        )).waitFor({timeout: 120000});
        report.checks.push(`${id}:${delegate}:tap`);
      }
      await page.screenshot({path: path.join(evidence, `${id}.png`)});
    }
    report.tasks.push(id);
  }
  assert.deepEqual(new Set(report.tasks), new Set(expected));
  enter('end');
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
  console.log(`Gallery journey passed: ${report.tasks.join(', ')}`);
  console.log(`Checks: ${report.checks.join(', ')}`);
} catch (error) {
  report.status = 'failed';
  report.error = String(error.stack || error);
  console.error(error);
  process.exitCode = 1;
  // Only a page that is still open can show where the step stopped.
  await page?.screenshot({path: path.join(evidence, 'failure.png'), timeout: 10000}).catch(() => {});
} finally {
  fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  closing = true;
  await browser.close();
}
