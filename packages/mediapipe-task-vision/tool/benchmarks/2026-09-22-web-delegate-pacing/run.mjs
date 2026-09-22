// Runs index.html in the installed Google Chrome, headed so WebGL uses the
// real GPU, and saves the result under results/. Extra --key=value arguments
// become page query parameters (for example --samples=100).
//
//   node packages/mediapipe-task-vision/tool/benchmarks/2026-09-22-web-delegate-pacing/run.mjs
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../../../..');
const {chromium} = await import(pathToFileURL(
  path.join(repo, 'gallery/tool/browser/node_modules/playwright/index.mjs')).href);

const types = {'.html': 'text/html', '.jpg': 'image/jpeg', '.js': 'text/javascript', '.mjs': 'text/javascript'};
const server = http.createServer((request, response) => {
  const file = path.join(repo, decodeURIComponent(new URL(request.url, 'http://x').pathname));
  if (!file.startsWith(repo) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, {'content-type': types[path.extname(file)] || 'application/octet-stream'});
  fs.createReadStream(file).pipe(response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

const query = new URLSearchParams({auto: '1'});
for (const argument of process.argv.slice(2)) {
  const [key, value] = argument.replace(/^--/, '').split('=');
  query.set(key, value);
}
const url = `http://127.0.0.1:${server.address().port}/` +
  `${path.relative(repo, here)}/index.html?${query}`;

const browser = await chromium.launch({channel: 'chrome', headless: false});
try {
  const page = await browser.newPage({viewport: {width: 1000, height: 800}});
  page.on('console', message => {
    if (message.type() === 'error' || message.type() === 'warning') console.log(`[page ${message.type()}] ${message.text()}`);
  });
  page.on('pageerror', error => console.log(`[page error] ${error.message}`));
  await page.goto(url);
  await page.bringToFront();
  let last = '';
  while (!(await page.evaluate(() => window.__benchmark?.done))) {
    const status = await page.textContent('#status');
    if (status !== last) console.log(status);
    last = status;
    await page.waitForTimeout(1000);
  }
  const {result, error} = await page.evaluate(() => window.__benchmark);
  if (error) throw new Error(error);
  result.environment.browserVersion = browser.version();
  result.environment.host = {platform: `${os.platform()} ${os.release()}`, cpu: os.cpus()[0]?.model};
  const stamp = result.environment.startedAt.replace(/[:.]/g, '-');
  const out = path.join(here, 'results', `${stamp}.json`);
  fs.mkdirSync(path.dirname(out), {recursive: true});
  // Readable, with each array of numbers (the raw samples) on one line.
  const text = JSON.stringify(result, null, 1)
    .replace(/\[\s+([-\d.eE,\s]+?)\s+\]/g, (_, body) => `[${body.replace(/\s+/g, '')}]`);
  fs.writeFileSync(out, text + '\n');
  console.log(`\n${result.worker.gpu.renderer} | Chrome ${browser.version()} | display ` +
              `${result.environment.displayRefreshHz} Hz | background load: ${result.settings.load}`);
  const pooled = (outputs, period, delegate) => {
    const values = result.blocks.filter(b => b.outputs === outputs && b.period === period && b.delegate === delegate)
      .flatMap(b => b.samples).sort((a, b) => a - b);
    return values[Math.floor(values.length / 2)];
  };
  for (const outputs of result.settings.outputs) {
    console.log(`\n${outputs}: median ms per detectForVideo (each block's median in brackets)`);
    for (const period of result.settings.periods) {
      const blocks = delegate => result.blocks
        .filter(b => b.outputs === outputs && b.period === period && b.delegate === delegate)
        .map(b => b.inference.median.toFixed(2)).join(', ');
      const label = period ? `${period} ms apart` : 'back to back';
      console.log(`  ${label.padEnd(16)} CPU ${pooled(outputs, period, 'CPU').toFixed(2)} [${blocks('CPU')}]` +
                  `   GPU ${pooled(outputs, period, 'GPU').toFixed(2)} [${blocks('GPU')}]`);
    }
  }
  console.log(`\nSaved ${path.relative(repo, out)}`);
} finally {
  await browser.close();
  server.close();
}
