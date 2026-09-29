import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const base = process.env.GALLERY_WEB_URL || 'http://127.0.0.1:8866/mediapipe_flutter/';
const portrait = path.join(repo, 'packages/mediapipe-task-vision/test/fixtures/face_detection/landmark-ex1.jpg');
const evidence = path.join(repo, 'build/codex-tmp/face-still-image-web');
fs.mkdirSync(evidence, {recursive: true});

const browser = await chromium.launch({channel: 'chromium', headless: true});
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  await page.goto(base);
  await page.getByRole('button', {name: /Face Landmarker/}).click();
  await page.getByText('MODE', {exact: true}).waitFor();
  await page.getByText('Camera', {exact: true}).click();
  await page.waitForTimeout(500);
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await page.getByRole('button', {name: 'Choose image'}).waitFor();

  const chooserPromise = page.waitForEvent('filechooser');
  await page.getByRole('button', {name: 'Choose image'}).click();
  const chooser = await chooserPromise;
  await chooser.setFiles({
    name: 'portrait.jpg',
    mimeType: 'image/jpeg',
    buffer: fs.readFileSync(portrait),
  });
  await page.getByText('1 face detected', {exact: true}).waitFor({timeout: 120000});
  assert.equal(await page.getByText('portrait.jpg', {exact: true}).count(), 1);
  assert.deepEqual(errors, []);
  await page.screenshot({path: path.join(evidence, 'result.png')});
  fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify({
    platform: 'web',
    checks: ['mode-dropdown', 'file-picker', 'real-image-inference', 'visible-face-result'],
    errors,
  }, null, 2) + '\n');
  console.log('Face Landmarker still image passed in Chromium.');
} finally {
  await browser.close();
}
