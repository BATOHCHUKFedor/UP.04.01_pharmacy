'use strict';

// Проверка настоящей браузерной блокировки CORS без npm-зависимостей.
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { createMockServer } = require('../mock-server');

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const listen = server => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', () => resolve(server.address().port));
});
const close = server => new Promise(resolve => {
  server.close(resolve);
  server.closeAllConnections();
});

class DevTools {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 0;
    this.pending = new Map();
    this.logs = [];
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.method === 'Log.entryAdded') this.logs.push(message.params.entry);
      const pending = this.pending.get(message.id);
      if (pending) {
        this.pending.delete(message.id);
        clearTimeout(pending.timer);
        message.error ? pending.reject(new Error(message.error.message)) : pending.resolve(message.result);
      }
    });
  }
  static async connect(url) {
    const socket = new WebSocket(url);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    return new DevTools(socket);
  }
  call(method, params = {}) {
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`Timeout: ${method}`)); }, 15000);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }
  async evaluate(expression) {
    const response = await this.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
    return response.result.value;
  }
}

async function main() {
  const supplied = process.argv.indexOf('--browser');
  const browserPath = supplied < 0 ? [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  ].find(candidate => fs.existsSync(candidate)) : process.argv[supplied + 1];
  if (!browserPath) throw new Error('Не найден Chromium-браузер. Укажите --browser <путь>.');
  const tempRoot = path.resolve(os.tmpdir());
  const profile = fs.mkdtempSync(path.join(tempRoot, 'pharmacy-cors-browser-'));
  const client = http.createServer((_, res) => {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<!doctype html><title>CORS test</title><p>Pharmacy API CORS probe</p>');
  });
  let api, browser, devTools;
  try {
    const clientPort = await listen(client);
    const origin = `http://127.0.0.1:${clientPort}`;
    api = createMockServer({ origin: 'http://localhost:5555', logger: null });
    const apiPort = await listen(api);
    const endpoint = `http://127.0.0.1:${apiPort}/api/__health`;
    browser = spawn(browserPath, ['--headless=new', '--no-first-run', '--no-default-browser-check',
      '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'],
    { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    const debuggerUrl = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Браузер не открыл DevTools')), 15000);
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
    await devTools.call('Page.navigate', { url: origin });
    for (let n = 0; n < 100; n++) {
      if (await devTools.evaluate('location.origin') === origin) break;
      await pause(100);
    }
    const probe = url => devTools.evaluate(`(async () => {
      try {
        const response = await fetch(${JSON.stringify(url)}, {
          headers: {'Content-Type': 'application/json'}, cache: 'no-store'
        });
        return {status: response.status, body: await response.json()};
      } catch (error) { return {error: error.message}; }
    })()`);
    const blocked = await probe(endpoint);
    assert.ok(blocked.error, 'Несовпадающий Origin должен блокироваться браузером');
    await pause(100);
    const corsLog = devTools.logs.find(entry => /CORS|Access-Control-Allow-Origin/.test(entry.text));
    assert.ok(corsLog, 'Console должна содержать сообщение CORS');
    console.log(`Несовпадающий Origin: ${blocked.error}`);
    console.log(`Console: ${corsLog.text}`);
    await close(api);
    api = createMockServer({ origin, logger: null });
    await new Promise((resolve, reject) => {
      api.once('error', reject);
      api.listen(apiPort, '127.0.0.1', resolve);
    });
    const allowed = await probe(`${endpoint}?retry=1`);
    assert.equal(allowed.status, 200);
    assert.equal(allowed.body.status, 'ok');
    console.log(`После настройки --origin ${origin}: HTTP ${allowed.status}, status=${allowed.body.status}`);
    console.log('Браузерная проверка CORS пройдена.');
  } finally {
    devTools?.socket.close();
    if (browser) {
      const exited = new Promise(resolve => browser.once('exit', resolve));
      browser.kill();
      await Promise.race([exited, pause(3000)]);
    }
    if (api?.listening) await close(api);
    if (client.listening) await close(client);
    // Удаляется только созданный этим тестом временный профиль.
    assert.equal(path.dirname(path.resolve(profile)), tempRoot);
    assert.ok(path.basename(profile).startsWith('pharmacy-cors-browser-'));
    fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
  }
}

module.exports = { DevTools, pause };
if (require.main === module) {
  main().catch(error => { console.error(error); process.exitCode = 1; });
}
