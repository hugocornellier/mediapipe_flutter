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
  // A category row is a progress bar labelled "<category> <score>"; the
  // sample's own category must score at least 0.5, not merely be listed.
  language_detector: {title: 'Language Detector', text: true, row: /^fr (0\.[5-9]|1\.0)/},
  text_classifier: {title: 'Text Classifier', text: true, row: /^positive (0\.[5-9]|1\.0)/},
  text_embedder: {title: 'Text Embedder', text: true, result: /Cosine similarity: -?\d+\.\d+/},
};

// The delegates each page must offer and run come from the coverage matrix the
// gate enforces: a required web GPU cell that the UI stops offering fails here.
const matrix = JSON.parse(fs.readFileSync(path.join(repo, 'tool/coverage/matrix.json'), 'utf8')).cells;
const delegatesFor = id => ['cpu', 'gpu'].filter(delegate => matrix[id]?.web?.[delegate] === 'required');

const report = {browser: browserName, checks: [], tasks: [], errors: []};
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
try {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}});
  try {
    await context.grantPermissions(['camera'], {origin: new URL(base).origin});
  } catch {
    // Firefox takes camera access from the preference above instead.
  }
  const page = await context.newPage();
  page.on('pageerror', error => report.errors.push(String(error)));
  page.on('response', response => {
    if (response.status() >= 400) report.errors.push(`${response.status()} ${response.url()}`);
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
  // A segment of a CPU/GPU control; clicking waits until the page enables it.
  const delegateButton = delegate => page.getByRole('button', {name: delegate.toUpperCase(), exact: true});
  // The live page's stats line counts recent frames on the running delegate.
  const liveFrames = delegate =>
    page.getByText(new RegExp(`over the last [1-9]\\d* ${delegate.toUpperCase()} frames`));
  // A still image result names the delegate that produced it.
  const stillRan = delegate =>
    page.getByText(new RegExp(`^Inference \\d+\\.\\d ms on ${delegate.toUpperCase()}$`));
  await page.goto(base);
  await sidebarItem('Home').waitFor({timeout: 120000});

  for (const id of expected) {
    const spec = cases[id];
    const item = sidebarItem(spec.title);
    await item.click();
    await page.getByText(spec.title, {exact: true}).last().waitFor();
    if (spec.sample) {
      const delegates = delegatesFor(id);
      assert.ok(delegates.length > 0, `${id} has no required web delegate`);
      // The page opens with the camera running. Each delegate must keep frames
      // coming, and the second is reached by switching while the camera runs.
      for (const delegate of delegates) {
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        await liveFrames(delegate).waitFor({timeout: 120000});
        report.checks.push(`${id}:${delegate}:live`);
      }
      await page.screenshot({path: path.join(evidence, `${id}-live.png`)});
      await page.getByRole('button', {name: 'Camera', exact: true}).click();
      await page.getByRole('menuitem', {name: 'Still image', exact: true}).click();
      const choose = page.getByRole('button', {name: 'Choose image'});
      await choose.waitFor();
      const chooserPromise = page.waitForEvent('filechooser');
      await choose.click();
      const chooser = await chooserPromise;
      await chooser.setFiles(path.join(repo, 'gallery/assets/samples', spec.sample));
      // The image runs on the delegate the camera ended on; switching back
      // runs it again on the other.
      for (const delegate of [...delegates].reverse()) {
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        await stillRan(delegate).waitFor({timeout: 120000});
        await page.getByText(spec.result).waitFor();
        report.checks.push(`${id}:${delegate}:still`);
      }
      assert.equal(await page.getByText(spec.sample, {exact: true}).count(), 1);
      await page.screenshot({path: path.join(evidence, `${id}-still.png`)});
    } else if (spec.text) {
      await page.getByRole('button', {name: id === 'text_embedder' ? 'Compare' : 'Run', exact: true}).click();
      await (spec.row ? page.getByRole('progressbar', {name: spec.row}) : page.getByText(spec.result))
        .waitFor({timeout: 120000});
      await page.getByText(/Done in \d+\.\d ms/).waitFor();
      report.checks.push(`${id}:cpu:run`);
    } else if (spec.audio) {
      // Each timestamped row is one group labelled with its top categories.
      await page.getByRole('group', {name: /^0\.00 s Speech \d\.\d{3}/}).waitFor({timeout: 120000});
      await page.getByText(/Done in \d+\.\d ms/).waitFor();
      report.checks.push(`${id}:cpu:run`);
    } else if (spec.segment) {
      const delegates = delegatesFor(id);
      assert.ok(delegates.length > 0, `${id} has no required web delegate`);
      for (const delegate of delegates) {
        // Switching reopens the task, so the image is tapped again after it.
        if (delegates.length > 1) await delegateButton(delegate).click({timeout: 120000});
        await page.getByRole('button', {name: 'Segmentation image', exact: true}).click({timeout: 120000});
        await page.getByText(new RegExp(
          `\\d+\\.\\d ms on ${delegate.toUpperCase()}\\s+·\\s+\\d+ requests, \\d+ coalesced`,
        )).waitFor({timeout: 120000});
        report.checks.push(`${id}:${delegate}:tap`);
      }
      await page.screenshot({path: path.join(evidence, `${id}.png`)});
    }
    report.tasks.push(id);
  }
  assert.deepEqual(new Set(report.tasks), new Set(expected));
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
  console.log(`Gallery journey passed: ${report.tasks.join(', ')}`);
  console.log(`Checks: ${report.checks.join(', ')}`);
} catch (error) {
  report.status = 'failed';
  report.error = String(error.stack || error);
  console.error(error);
  process.exitCode = 1;
} finally {
  fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close();
}
