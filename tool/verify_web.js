'use strict';

// Smoke-проверка собранного Flutter Web в Chromium. Порты 5555/8080 должны быть свободны.
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { createMockServer } = require('../mock-server');
const { DevTools, pause } = require('./verify_cors');

const start = (server, port) => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(port, '127.0.0.1', resolve);
});
const close = server => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });

async function main() {
  const webRoot = path.resolve(__dirname, '../build/web');
  assert.ok(fs.existsSync(path.join(webRoot, 'main.dart.js')), 'Сначала выполните flutter build web');
  const root = path.resolve(os.tmpdir());
  const profile = fs.mkdtempSync(path.join(root, 'pharmacy-web-browser-'));
  const evidence = path.resolve(__dirname, '../build/verification');
  fs.mkdirSync(evidence, { recursive: true });
  const types = { '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf' };
  const client = http.createServer((req, res) => {
    const requested = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    let file = path.resolve(webRoot, `.${requested}`);
    if (file !== webRoot && !file.startsWith(webRoot + path.sep)) { res.writeHead(403); res.end(); return; }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(webRoot, 'index.html');
    res.setHeader('Content-Type', types[path.extname(file)] ?? 'application/octet-stream');
    // Используем локальный CanvasKit, не меняя файлы сборки или приложения.
    if (path.basename(file) === 'flutter_bootstrap.js') {
      res.end(fs.readFileSync(file, 'utf8').replace('_flutter.loader.load({',
        "_flutter.loader.load({config: {canvasKitBaseUrl: '/canvaskit/'},"));
    } else fs.createReadStream(file).pipe(res);
  });
  const requests = [];
  let api = createMockServer({ origin: 'http://localhost:5555', logger: line => requests.push(line) });
  let browser, devTools;
  try {
    await start(client, 5555);
    await start(api, 8080);
    const candidates = ['C:/Program Files/Google/Chrome/Application/chrome.exe',
      'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'];
    const browserPath = candidates.find(candidate => fs.existsSync(candidate));
    assert.ok(browserPath, 'Не найден Chromium-браузер');
    browser = spawn(browserPath, ['--headless=new', '--no-first-run', '--no-default-browser-check',
      '--enable-unsafe-swiftshader', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'],
    { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    const debuggerUrl = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('DevTools timeout')), 15000);
      let output = '';
      browser.once('error', reject);
      browser.stderr.on('data', chunk => {
        output += chunk;
        const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
        if (match) { clearTimeout(timer); resolve(match[1]); }
      });
    });
    const debuggerOrigin = new URL(debuggerUrl).origin.replace('ws:', 'http:');
    const target = await (await fetch(`${debuggerOrigin}/json/new?about:blank`, { method: 'PUT' })).json();
    devTools = await DevTools.connect(target.webSocketDebuggerUrl);
    await devTools.call('Page.enable');
    await devTools.call('Log.enable');
    await devTools.call('Emulation.setDeviceMetricsOverride', {
      width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false,
    });
    async function navigate(route, expectedText) {
      await devTools.call('Page.navigate', { url: `http://localhost:5555${route}` });
      for (let n = 0; n < 200; n++) {
        await devTools.evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
        const text = await devTools.evaluate("document.body?.innerText ?? ''");
        if (text.includes(expectedText)) return;
        await pause(100);
      }
      throw new Error(`Не найден текст «${expectedText}» на ${route}. Console: ${JSON.stringify(devTools.logs)}`);
    }
    async function screenshot(name) {
      const result = await devTools.call('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(path.join(evidence, `${name}.png`), Buffer.from(result.data, 'base64'));
    }
    await navigate('/drugs?sort=id,asc', 'Парацетамол');
    await screenshot('drugs-table');
    await navigate('/drugs?sort=id,asc&page=2', 'Каптоприл');
    assert.ok(requests.some(line => /GET \/api\/drugs\?.*page=2.*→ 200/.test(line)));
    await navigate('/drugs?search=невозможный-запрос', 'По заданным условиям записей нет');
    await screenshot('empty-result');
    await navigate('/drugs?__fail=500', 'Принудительная ошибка');
    await screenshot('server-500');
    const before = Date.now();
    await devTools.call('Page.navigate', { url: 'http://localhost:5555/drugs?__delay=1500' });
    await pause(900);
    await screenshot('loading');
    for (let n = 0; n < 200; n++) {
      await devTools.evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
      if ((await devTools.evaluate("document.body?.innerText ?? ''")).includes('Ибупрофен')) break;
      await pause(100);
    }
    assert.ok(Date.now() - before >= 1500);
    assert.ok(requests.some(line => /__delay=1500.*→ 200/.test(line)));
    await close(api);
    await navigate('/drugs', 'Сервер недоступен');
    await screenshot('server-offline');
    api = createMockServer({ origin: 'http://localhost:5555', logger: line => requests.push(line) });
    await start(api, 8080);
    await navigate('/drugs', 'Ибупрофен');
    await devTools.call('Emulation.setDeviceMetricsOverride', {
      width: 390, height: 1000, deviceScaleFactor: 1, mobile: false,
    });
    await pause(500);
    await screenshot('drugs-cards');
    const errors = devTools.logs.filter(entry => entry.level === 'error' &&
      !/500|ERR_CONNECTION_REFUSED/.test(entry.text));
    assert.deepEqual(errors, [], 'Неожиданные ошибки браузера');
    console.log('Flutter Web: таблица, новая страница, пустой результат, 500, задержка, остановленный сервер и карточки — проверены.');
    console.log(`Снимки: ${evidence}`);
  } finally {
    devTools?.socket.close();
    if (browser) {
      const exited = new Promise(resolve => browser.once('exit', resolve));
      browser.kill();
      await Promise.race([exited, pause(3000)]);
    }
    if (api.listening) await close(api);
    if (client.listening) await close(client);
    assert.equal(path.dirname(path.resolve(profile)), root);
    assert.ok(path.basename(profile).startsWith('pharmacy-web-browser-'));
    fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
