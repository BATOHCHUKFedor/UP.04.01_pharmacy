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
  let timeOffset = 0;
  const serverOptions = { origin: 'http://localhost:5555', ttl: 60, now: () => Date.now() + timeOffset,
    logger: line => requests.push(line) };
  let api = createMockServer(serverOptions);
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
    await devTools.call('Network.enable');
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
      throw new Error(`Не найден текст «${expectedText}» на ${route}. Text: ${await devTools.evaluate("document.body?.innerText ?? ''")}. Console: ${JSON.stringify(devTools.logs)}`);
    }
    async function screenshot(name) {
      const result = await devTools.call('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(path.join(evidence, `${name}.png`), Buffer.from(result.data, 'base64'));
    }
    async function clickText(label) {
      const point = await devTools.evaluate(`(() => {
        const element = [...document.querySelectorAll('flt-semantics[role="button"], button')]
          .find(e => (e.innerText || e.getAttribute('aria-label') || '').trim() === ${JSON.stringify(label)});
        if (!element) return null;
        const r = element.getBoundingClientRect(); return {x: r.x + r.width / 2, y: r.y + r.height / 2};
      })()`);
      assert.ok(point, `Не найдена кнопка ${label}`);
      await devTools.call('Input.dispatchMouseEvent', { type: 'mousePressed', ...point, button: 'left', clickCount: 1 });
      await devTools.call('Input.dispatchMouseEvent', { type: 'mouseReleased', ...point, button: 'left', clickCount: 1 });
    }
    async function fillInput(index, value) {
      const point = await devTools.evaluate(`(() => {
        const element = [...document.querySelectorAll('flt-semantics input')][${index}];
        if (!element) return null;
        const r = element.getBoundingClientRect(); return {x: r.x + r.width / 2, y: r.y + r.height / 2};
      })()`);
      assert.ok(point, `Не найдено поле ${index}`);
      await devTools.call('Input.dispatchMouseEvent', { type: 'mousePressed', ...point, button: 'left', clickCount: 1 });
      await devTools.call('Input.dispatchMouseEvent', { type: 'mouseReleased', ...point, button: 'left', clickCount: 1 });
      await devTools.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'a', code: 'KeyA', modifiers: 2, windowsVirtualKeyCode: 65 });
      await devTools.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'a', code: 'KeyA', modifiers: 2, windowsVirtualKeyCode: 65 });
      await devTools.evaluate("document.activeElement?.select?.()");
      await devTools.call('Input.insertText', { text: value });
      await pause(150);
    }
    async function waitText(expectedText) {
      for (let n = 0; n < 200; n++) {
        await devTools.evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
        if ((await devTools.evaluate("document.body?.innerText ?? ''")).includes(expectedText)) return;
        await pause(100);
      }
      throw new Error(`Не найден ${expectedText}: ${await devTools.evaluate("document.body?.innerText ?? ''")}`);
    }
    async function installSession(username, password, {forged = false, brokenRefresh = false} = {}) {
      // Тот же формат SharedPreferencesAsync Web; только временный профиль проверки.
      await devTools.evaluate(`(async () => {
        const response = await fetch('http://localhost:8080/api/auth/login', {method:'POST',
          headers:{'Content-Type':'application/json'}, body:JSON.stringify(${JSON.stringify({ username, password })})});
        const session = await response.json(); if (!response.ok) throw Error(session.message);
        session.lastActivity = session.session.lastActivity;
        ${forged ? "session.user.role = 'admin';" : ''}
        ${brokenRefresh ? "session.refreshToken = 'invalid-refresh';" : ''}
        localStorage.setItem('pharmacy.auth.v1', JSON.stringify(JSON.stringify(session)));
      })()`);
    }
    await navigate('/login', 'Вход в аптечный каталог');
    await screenshot('auth-login');
    await navigate('/register', 'Регистрация');
    await fillInput(0, 'Тестовый пользователь'); await fillInput(1, 'browser-user');
    await fillInput(2, 'short'); await waitText('Пароль: от 8 до 128 символов');
    await screenshot('auth-registration-password');
    await fillInput(2, 'Browser123!'); await fillInput(3, 'Browser123!');
    await clickText('Зарегистрироваться'); await waitText('Здравствуйте, Тестовый пользователь');
    await clickText('Выйти'); await waitText('Вход в аптечный каталог');
    assert.equal(await devTools.evaluate("localStorage.getItem('pharmacy.auth.v1')"), null);
    await navigate('/drugs/2?returnTest=1', 'Вход в аптечный каталог');
    await fillInput(0, 'customer'); await fillInput(1, 'Customer123!'); await clickText('Войти');
    await waitText('Ибупрофен');
    assert.ok((await devTools.evaluate('location.pathname + location.search')).includes('/drugs/2?returnTest=1'));
    await navigate('/', 'Здравствуйте, Анна Пользователь');
    await screenshot('auth-user-home');
    await navigate('/drugs?sort=id,asc', 'Парацетамол');
    const userText = await devTools.evaluate("document.body.innerText");
    assert.ok(!userText.includes('Удалить навсегда') && !userText.includes('Логически удалить'));
    await navigate('/admin/users', 'Доступ запрещён');
    await screenshot('auth-forbidden');
    await navigate('/my-reservations', 'Бронирований пока нет');
    // Проверяем настоящий истёкший access, не подменяя сам JWT.
    timeOffset += 61000;
    await navigate('/drugs?sort=id,asc', 'Парацетамол');
    assert.ok(requests.some(line => /POST \/api\/auth\/refresh.*→ 200/.test(line)));
    await installSession('customer', 'Customer123!', {forged: true});
    await navigate('/drugs/2', 'Удалить навсегда');
    await screenshot('auth-forged-admin-buttons');
    await clickText('Удалить навсегда'); await waitText('Удалить запись навсегда?');
    await clickText('Удалить'); await waitText('Недостаточно прав');
    await screenshot('auth-server-403');
    assert.ok(requests.some(line => /DELETE \/api\/drugs\/2\?hard=true.*→ 403/.test(line)));
    assert.ok(devTools.network.some(response => response.url.endsWith('/api/drugs/2?hard=true') && response.status === 403));
    await installSession('pharmacist', 'Pharmacist123!');
    await navigate('/work/reservations', 'Бронирований пока нет');
    await screenshot('auth-pharmacist-workspace');
    await installSession('admin', 'Admin123!');
    await navigate('/admin/users', 'Пользователи и роли');
    await screenshot('auth-admin-users');
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
    api = createMockServer(serverOptions);
    await start(api, 8080);
    await installSession('admin', 'Admin123!');
    await navigate('/drugs', 'Ибупрофен');
    await devTools.call('Emulation.setDeviceMetricsOverride', {
      width: 390, height: 1000, deviceScaleFactor: 1, mobile: false,
    });
    await pause(500);
    await screenshot('drugs-cards');
    await devTools.call('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
    await installSession('customer', 'Customer123!', {brokenRefresh: true});
    timeOffset += 61000;
    const beforeFailure = requests.length;
    await navigate('/drugs', 'Вход в аптечный каталог');
    await screenshot('auth-refresh-failed');
    assert.equal(requests.slice(beforeFailure).filter(line => /POST \/api\/auth\/refresh.*→ 401/.test(line)).length, 1);
    assert.equal(await devTools.evaluate("localStorage.getItem('pharmacy.auth.v1')"), null);
    // Короткие сроки лишь у временного сервера проверки, не у рабочего приложения.
    await close(api); timeOffset = 0;
    api = createMockServer({ ...serverOptions, idleTtl: 8 }); await start(api, 8080);
    await installSession('customer', 'Customer123!');
    await navigate('/', 'Здравствуйте, Анна Пользователь');
    await waitText('Выход через'); await screenshot('auth-idle-warning');
    await waitText('Вход в аптечный каталог'); await screenshot('auth-idle-logout');
    await close(api);
    api = createMockServer({ ...serverOptions, sessionTtl: 8 }); await start(api, 8080);
    await installSession('customer', 'Customer123!');
    await navigate('/', 'Здравствуйте, Анна Пользователь');
    await waitText('Максимальная длительность сессии истекла');
    await screenshot('auth-absolute-logout');
    const errors = devTools.logs.filter(entry => entry.level === 'error' &&
      !/401|403|500|ERR_CONNECTION_REFUSED/.test(entry.text));
    assert.deepEqual(errors, [], 'Неожиданные ошибки браузера');
    console.log('Flutter Web: вход, роли, redirect, refresh истёкшего JWT, подмена роли и 403, каталог и состояния ПР4 — проверены.');
    console.log(`Снимки: ${evidence}`);
    fs.writeFileSync(path.join(evidence, 'auth-network.json'), JSON.stringify(devTools.network.filter(response => response.url.includes('/api/')), null, 2));
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
