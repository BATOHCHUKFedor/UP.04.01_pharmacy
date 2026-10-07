'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { optimizeRelease } = require('./optimize_release');

test('Упаковка исключает только .symbols, сохраняет ресурсы и не перезаписывает данные', t => {
  const tempRoot = path.resolve(os.tmpdir());
  const workspace = fs.mkdtempSync(path.join(tempRoot, 'pharmacy-pack-test-'));
  t.after(() => {
    const resolved = path.resolve(workspace);
    assert.equal(path.dirname(resolved), tempRoot);
    assert.ok(path.basename(resolved).startsWith('pharmacy-pack-test-'));
    fs.rmSync(resolved, { recursive: true, force: true });
  });
  const source = path.join(workspace, 'source');
  const output = path.join(workspace, 'output');
  fs.mkdirSync(path.join(source, 'canvaskit'), { recursive: true });
  const fixture = {
    'index.html': '<html>fixture</html>',
    'flutter_bootstrap.js': 'bootstrap',
    'main.dart.js': 'application',
    'canvaskit/canvaskit.wasm': 'wasm fixture',
    'canvaskit/canvaskit.js.symbols': 'debug symbols',
  };
  for (const [relative, content] of Object.entries(fixture)) fs.writeFileSync(path.join(source, relative), content);
  const result = optimizeRelease(source, output);
  assert.equal(result.beforeFiles, 5);
  assert.equal(result.afterFiles, 4);
  assert.equal(result.savedBytes, Buffer.byteLength('debug symbols'));
  assert.equal(result.removed[0].file, 'canvaskit/canvaskit.js.symbols');
  for (const [relative, content] of Object.entries(fixture)) {
    assert.equal(fs.readFileSync(path.join(source, relative), 'utf8'), content);
    if (relative.endsWith('.symbols')) assert.ok(!fs.existsSync(path.join(output, relative)));
    else assert.equal(fs.readFileSync(path.join(output, relative), 'utf8'), content);
  }
  assert.throws(() => optimizeRelease(source, output), /Результат уже существует/);
  assert.throws(() => optimizeRelease(source, source), /раздельными каталогами/);
  assert.throws(() => optimizeRelease(source, path.join(source, 'nested')), /раздельными каталогами/);
});
