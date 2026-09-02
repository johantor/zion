// Renders the mockups to PNG. Needs Playwright (local node_modules or `npm i -g playwright`)
// and a Chromium it can find. Run: node docs/mockups/crew-view/render.mjs
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); }
catch { pw = require(execSync('npm root -g').toString().trim() + '/playwright'); }
const dir = new URL('.', import.meta.url).pathname;
const shots = [
  ['a-ladder.html', 'a-ladder-running.png', { width: 1280, height: 900 }],
  ['a-ladder.html?needs', 'a-ladder-needs-you.png', { width: 1280, height: 900 }],
  ['b-lanes.html', 'b-lanes.png', { width: 1280, height: 1000 }],
  ['c-board.html', 'c-board-needs-you.png', { width: 1280, height: 820 }],
  ['d-strip.html', 'd-strip.png', { width: 1100, height: 130 }],
];
const browser = await pw.chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
for (const [src, out, vp] of shots) {
  await page.setViewportSize(vp);
  await page.goto('file://' + dir + src);
  await page.waitForTimeout(150);
  await page.screenshot({ path: dir + out });
  console.log('wrote', out);
}
await browser.close();
