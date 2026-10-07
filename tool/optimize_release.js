'use strict';

// Упаковка release без отладочных таблиц символов; исходная сборка не меняется.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function listFiles(directory, prefix = '') {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const relative = path.join(prefix, entry.name);
    if (entry.isDirectory()) return listFiles(path.join(directory, entry.name), relative);
    assert.ok(entry.isFile(), `Необычный файл в сборке: ${relative}`);
    return [relative];
  }).sort();
}

function isWithin(parent, child) {
  const relative = path.relative(parent, child);
  return relative !== '' && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative);
}

function optimizeRelease(input, output) {
  const source = path.resolve(input);
  const destination = path.resolve(output);
  assert.ok(source !== destination && !isWithin(source, destination) && !isWithin(destination, source),
    'Исходная сборка и результат должны быть раздельными каталогами');
  assert.ok(!fs.existsSync(destination), 'Результат уже существует: перезапись отключена');
  assert.ok(fs.existsSync(path.join(source, 'index.html')), 'В исходном каталоге нет index.html');
  assert.ok(fs.existsSync(path.join(source, 'flutter_bootstrap.js')), 'Нет загрузчика Flutter');
  const files = listFiles(source);
  const removed = [];
  let beforeBytes = 0;
  let afterBytes = 0;
  fs.mkdirSync(destination, { recursive: true });
  for (const relative of files) {
    const file = path.join(source, relative);
    const bytes = fs.statSync(file).size;
    beforeBytes += bytes;
    if (relative.endsWith('.symbols')) {
      removed.push({ file: relative.split(path.sep).join('/'), bytes });
      continue;
    }
    const target = path.join(destination, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(file, target, fs.constants.COPYFILE_EXCL);
    afterBytes += bytes;
  }
  return {
    source, destination,
    beforeFiles: files.length,
    afterFiles: files.length - removed.length,
    beforeBytes, afterBytes,
    savedBytes: beforeBytes - afterBytes,
    savedPercent: beforeBytes ? Number(((beforeBytes - afterBytes) / beforeBytes * 100).toFixed(2)) : 0,
    removed,
  };
}

if (require.main === module) {
  try {
    const args = process.argv.slice(2);
    const option = (name, fallback) => {
      const index = args.indexOf(name);
      if (index < 0) return fallback;
      assert.ok(args[index + 1] && !args[index + 1].startsWith('--'), `Нет значения ${name}`);
      return args[index + 1];
    };
    const projectRoot = path.resolve(__dirname, '..');
    const input = option('--input', path.join(projectRoot, 'build/web'));
    const output = path.resolve(option('--output', path.join(projectRoot, 'build/pr6-builds/optimized')));
    assert.ok(isWithin(path.join(projectRoot, 'build'), output), 'Результат должен находиться внутри каталога build проекта');
    const result = optimizeRelease(input, output);
    console.table([{
      beforeMB: Number((result.beforeBytes / 1000000).toFixed(2)),
      afterMB: Number((result.afterBytes / 1000000).toFixed(2)),
      savedMB: Number((result.savedBytes / 1000000).toFixed(2)),
      savedPercent: result.savedPercent,
    }]);
    console.log(`Не включено таблиц символов: ${result.removed.length}; исходные файлы сохранены.`);
    console.log(`Каталог публикации: ${result.destination}`);
    const evidence = path.join(projectRoot, 'build/pr6-builds');
    fs.mkdirSync(evidence, { recursive: true });
    const filename = `optimization-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
    fs.writeFileSync(path.join(evidence, filename), JSON.stringify(result, null, 2), { flag: 'wx' });
    console.log(`Измерения: ${path.join(evidence, filename)}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { optimizeRelease };
