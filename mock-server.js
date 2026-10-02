'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const seed = require('./server/seed-data.json');
const kinds = ['drugs', 'suppliers', 'manufacturers', 'categories', 'licenses'];

class HttpError extends Error {
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}
const invalid = errors => { throw new HttpError(422, 'Проверьте поля формы.', errors); };

function createMockServer({ origin = 'http://localhost:5555', data = seed,
  dataFile = null, logger = console.log } = {}) {
  let db = structuredClone(data);
  if (dataFile && fs.existsSync(dataFile)) {
    db = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
  }
  if (db.version !== 1 || kinds.some(kind => !Array.isArray(db[kind]))) {
    throw new Error('Неподдерживаемый формат серверного каталога. Сохраните файл и выполните миграцию.');
  }
  db.nextIds ??= Object.fromEntries(kinds.map(kind =>
    [kind, Math.max(0, ...db[kind].map(item => item.id)) + 1]));

  const lookup = (rows, kind, id) => rows[kind].find(item => item.id === id);
  const active = (rows, kind, id) => {
    const item = lookup(rows, kind, id);
    return item && !item.deletedAt;
  };
  function existing(kind, id) {
    const item = lookup(db, kind, id);
    if (!item) throw new HttpError(404, 'Запись не найдена.');
    return item;
  }
  function expand(kind, item) {
    const result = structuredClone(item);
    if (kind === 'drugs') {
      result.manufacturer = lookup(db, 'manufacturers', item.manufacturerId) ?? null;
      result.supplier = lookup(db, 'suppliers', item.supplierId) ?? null;
      result.categories = item.categoryIds.map(id => lookup(db, 'categories', id)).filter(Boolean);
      delete result.manufacturerId;
      delete result.supplierId;
      delete result.categoryIds;
    } else if (kind === 'suppliers') {
      result.manufacturers = item.manufacturerIds.map(id => lookup(db, 'manufacturers', id)).filter(Boolean);
      result.license = db.licenses.find(l => l.supplierId === item.id) ?? null;
      delete result.manufacturerIds;
    } else if (kind === 'licenses') {
      result.supplier = lookup(db, 'suppliers', item.supplierId) ?? null;
      delete result.supplierId;
    }
    return result;
  }
  function commit(next) {
    if (dataFile) {
      fs.mkdirSync(path.dirname(dataFile), { recursive: true });
      const temporary = `${dataFile}.tmp`;
      fs.writeFileSync(temporary, JSON.stringify(next, null, 2), 'utf8');
      fs.renameSync(temporary, dataFile);
    }
    db = next;
  }

  function transaction(change) {
    const next = structuredClone(db);
    const result = change(next);
    commit(next);
    return result;
  }
  function validate(rows, kind, body, id) {
    const errors = {};
    const value = { id, deletedAt: lookup(rows, kind, id)?.deletedAt ?? null };
    function text(key, limit) {
      const entered = typeof body[key] === 'string' ? body[key].trim() : '';
      value[key] = entered;
      if (!entered) errors[key] = 'Заполните поле';
      else if (entered.length > limit) errors[key] = `Не более ${limit} символов`;
    }
    function number(key, min, max, integer = true) {
      value[key] = body[key];
      if (typeof body[key] !== 'number' || !Number.isFinite(body[key]) ||
          (integer && !Number.isInteger(body[key]))) {
        errors[key] = integer ? 'Введите целое число' : 'Введите число';
      } else if (body[key] < min || body[key] > max) errors[key] = `Число от ${min} до ${max}`;
    }
    function email(key) {
      text(key, 254);
      if (!errors[key] && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value[key])) {
        errors[key] = 'Введите корректный адрес почты';
      }
    }
    function reference(key, target) {
      value[key] = body[key];
      if (!Number.isInteger(body[key]) || !active(rows, target, body[key])) {
        errors[key] = 'Выберите действующую запись';
      }
    }
    function references(key, target) {
      value[key] = Array.isArray(body[key]) ? [...new Set(body[key])] : [];
      if (!value[key].length || value[key].some(id => !Number.isInteger(id) || !active(rows, target, id))) {
        errors[key] = 'Выберите действующие записи';
      }
    }
    if (kind !== 'licenses') text('name', kind === 'categories' ? 100 : 120);
    if (kind === 'drugs') {
      text('registrationNumber', 40);
      reference('manufacturerId', 'manufacturers');
      reference('supplierId', 'suppliers');
      references('categoryIds', 'categories');
      number('productionYear', 1900, 2100);
      number('price', 0.01, 10000000, false);
      number('stock', 0, 1000000);
      if (rows.drugs.some(d => d.id !== id &&
          d.registrationNumber.toLowerCase() === value.registrationNumber.toLowerCase())) {
        errors.registrationNumber = 'Такой регистрационный номер уже существует';
      }
      if (!errors.supplierId && !errors.manufacturerId &&
          !lookup(rows, 'suppliers', value.supplierId).manufacturerIds.includes(value.manufacturerId)) {
        errors.supplierId = 'Поставщик не работает с выбранным производителем';
      }
    } else if (kind === 'suppliers') {
      text('contactPerson', 120);
      text('country', 80);
      text('phone', 30);
      email('email');
      number('partnershipYear', 1900, 2100);
      references('manufacturerIds', 'manufacturers');
      if (rows.suppliers.some(s => s.id !== id && s.email.toLowerCase() === value.email.toLowerCase())) {
        errors.email = 'Такой адрес почты уже существует';
      }
      if (rows.drugs.some(d => d.supplierId === id && !value.manufacturerIds.includes(d.manufacturerId))) {
        errors.manufacturerIds = 'Нельзя убрать производителя: с ним связаны препараты этого поставщика';
      }
    } else if (kind === 'manufacturers') {
      text('country', 80);
      email('contactEmail');
    } else if (kind === 'categories') {
      text('description', 250);
    } else {
      reference('supplierId', 'suppliers');
      text('number', 40);
      number('issuedYear', 1900, 2100);
      number('expiresYear', 1900, 2200);
      if (!errors.issuedYear && !errors.expiresYear && value.expiresYear < value.issuedYear) {
        errors.expiresYear = 'Год окончания должен быть не раньше года выдачи';
      }
      if (rows.licenses.some(l => l.id !== id && l.supplierId === value.supplierId)) {
        errors.supplierId = 'У этого поставщика уже есть лицензия';
      }
    }
    if (Object.keys(errors).length) invalid(errors);
    return value;
  }
  function save(rows, kind, body, id) {
    const item = validate(rows, kind, body, id);
    if (!id) {
      item.id = rows.nextIds[kind]++;
      rows[kind].push(item);
    } else {
      rows[kind][rows[kind].findIndex(other => other.id === id)] = item;
    }
    if (kind === 'suppliers' && body.license != null) {
      const original = rows.licenses.find(l => l.supplierId === item.id);
      try {
        const licenseBody = { ...body.license, supplierId: item.id };
        const license = save(rows, 'licenses', licenseBody, original?.id ?? 0);
        license.deletedAt = null;
      } catch (error) {
        if (error instanceof HttpError && error.status === 422) {
          error.errors = Object.fromEntries(Object.entries(error.errors)
            .map(([key, message]) => [key === 'number' ? 'licenseNumber' : key, message]));
        }
        throw error;
      }
    }
    return item;
  }
  function checkDeletion(rows, kind, id) {
    let count = 0;
    if (kind === 'manufacturers') count = rows.drugs.filter(d => d.manufacturerId === id).length;
    if (kind === 'suppliers') count = rows.drugs.filter(d => d.supplierId === id).length;
    if (kind === 'categories') count = rows.drugs.filter(d => d.categoryIds.includes(id)).length;
    if (count) throw new HttpError(409, `Удаление невозможно: связанных препаратов — ${count}`);
    if (kind === 'manufacturers') {
      count = rows.suppliers.filter(s => s.manufacturerIds.includes(id)).length;
      if (count) throw new HttpError(409, `Удаление невозможно: связанных поставщиков — ${count}`);
    }
  }
  function softDelete(rows, kind, id) {
    checkDeletion(rows, kind, id);
    const item = lookup(rows, kind, id);
    item.deletedAt ??= new Date().toISOString();
    if (kind === 'suppliers') {
      rows.licenses.filter(l => l.supplierId === id).forEach(l => { l.deletedAt = item.deletedAt; });
    }
    return item;
  }
  function list(kind, q) {
    let rows = db[kind].filter(item => q.get('includeDeleted') === 'true' || !item.deletedAt);
    const search = (q.get('search') ?? '').trim().toLowerCase();
    if (search) rows = rows.filter(item => {
      const searchable = kind === 'drugs' ? `${item.name} ${item.registrationNumber}` :
        kind === 'licenses' ? `${item.number} ${lookup(db, 'suppliers', item.supplierId)?.name ?? ''}` :
        `${item.name} ${item.contactPerson ?? ''} ${item.country ?? ''} ${item.email ?? ''} ${item.description ?? ''}`;
      return searchable.toLowerCase().includes(search);
    });
    const idMatches = (key, value) => !q.has(key) || Number(q.get(key)) === value;
    if (kind === 'drugs') rows = rows.filter(d =>
      (!q.has('categoryId') || d.categoryIds.includes(Number(q.get('categoryId')))) &&
      idMatches('manufacturerId', d.manufacturerId) && idMatches('supplierId', d.supplierId) &&
      (!q.has('yearFrom') || d.productionYear >= Number(q.get('yearFrom'))) &&
      (!q.has('yearTo') || d.productionYear <= Number(q.get('yearTo'))));
    if (kind === 'suppliers') rows = rows.filter(s =>
      (!q.has('manufacturerId') || s.manufacturerIds.includes(Number(q.get('manufacturerId')))) &&
      (!q.has('country') || s.country === q.get('country')));
    if (kind === 'manufacturers' && q.has('country')) rows = rows.filter(m => m.country === q.get('country'));
    if (kind === 'licenses') rows = rows.filter(l => idMatches('supplierId', l.supplierId) &&
      (!q.has('yearFrom') || l.expiresYear >= Number(q.get('yearFrom'))) &&
      (!q.has('yearTo') || l.expiresYear <= Number(q.get('yearTo'))));
    if (kind === 'categories' && q.get('usedOnly') === 'true') {
      const used = new Set(db.drugs.filter(d => !d.deletedAt).flatMap(d => d.categoryIds));
      rows = rows.filter(c => used.has(c.id));
    }
    const [field, direction] = (q.get('sort') ?? 'name,asc').split(',');
    const sortValue = item => field === 'name' ? (item.name ?? item.number) :
      field === 'year' ? (item.productionYear ?? item.partnershipYear) :
      field === 'email' ? (item.email ?? item.contactEmail) : item[field];
    rows.sort((a, b) => {
      const left = sortValue(a), right = sortValue(b);
      const result = typeof left === 'number' && typeof right === 'number'
        ? left - right : String(left ?? '').localeCompare(String(right ?? ''), 'ru');
      return (result || a.id - b.id) * (direction === 'desc' ? -1 : 1);
    });
    const total = rows.length;
    const size = [10, 25, 50].includes(Number(q.get('size'))) ? Number(q.get('size')) : 10;
    const requestedPage = Number(q.get('page'));
    const page = Math.min(Math.max(1, Math.ceil(total / size)),
      Number.isSafeInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1);
    return { items: rows.slice((page - 1) * size, page * size).map(item => expand(kind, item)), page, size, total };
  }
  async function readBody(req) {
    let bytes = 0, raw = '';
    req.setEncoding('utf8');
    for await (const chunk of req) {
      bytes += Buffer.byteLength(chunk);
      if (bytes > 1024 * 1024) throw new HttpError(413, 'Запрос слишком большой.');
      raw += chunk;
    }
    try {
      const body = raw ? JSON.parse(raw) : {};
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
      return body;
    } catch { throw new HttpError(400, 'Ожидается JSON-объект.'); }
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Vary', 'Origin');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.on('finish', () => logger?.(`${req.method} ${req.url} → ${res.statusCode}`));
    const send = (status, body) => { res.statusCode = status; res.end(body == null ? undefined : JSON.stringify(body)); };
    try {
      if (req.headers.origin && req.headers.origin !== origin) {
        throw new HttpError(403, `Источник ${req.headers.origin} не разрешён. Ожидается ${origin}.`);
      }
      if (req.method === 'OPTIONS') return send(204);
      const url = new URL(req.url, 'http://localhost');
      const delay = Math.min(30000, Math.max(0, Number(url.searchParams.get('__delay')) || 0));
      if (delay) await new Promise(resolve => setTimeout(resolve, delay));
      if (res.destroyed) return;
      if (url.searchParams.has('__fail')) {
        const status = Number(url.searchParams.get('__fail'));
        throw new HttpError(status >= 400 && status <= 599 ? status : 500, 'Принудительная ошибка учебного сервера.');
      }
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts[0] !== 'api') throw new HttpError(404, 'Ожидается адрес /api.');
      if (parts[1] === '__health' && req.method === 'GET') return send(200, { status: 'ok' });
      if (parts[1] === 'references' && req.method === 'GET') {
        return send(200, Object.fromEntries(kinds.filter(k => k !== 'drugs')
          .map(k => [k, db[k].map(item => expand(k, item))])));
      }
      const kind = parts[1];
      if (!kinds.includes(kind)) throw new HttpError(404, 'Ресурс не найден.');
      if (parts.length === 2 && req.method === 'GET') return send(200, list(kind, url.searchParams));
      if (parts.length === 2 && req.method === 'POST') {
        const body = await readBody(req);
        const item = transaction(rows => save(rows, kind, body, 0));
        return send(201, expand(kind, item));
      }
      if (parts[2] === 'bulk-delete' && parts.length === 3 && req.method === 'POST') {
        const body = await readBody(req);
        if (!Array.isArray(body.ids) || body.ids.some(id => !Number.isInteger(id) || id <= 0)) {
          invalid({ ids: 'Передайте список идентификаторов' });
        }
        const selected = transaction(rows => [...new Set(body.ids)]
          .filter(id => active(rows, kind, id)).map(id => softDelete(rows, kind, id)));
        return send(200, { deleted: selected.length, items: selected.map(item => expand(kind, item)),
          licenses: kind === 'suppliers' ? db.licenses.filter(l => body.ids.includes(l.supplierId)) : [] });
      }
      const id = Number(parts[2]);
      if (!Number.isSafeInteger(id) || id <= 0) throw new HttpError(404, 'Запись не найдена.');
      const item = existing(kind, id);
      if (parts.length === 3 && req.method === 'GET') return send(200, expand(kind, item));
      if (parts.length === 3 && req.method === 'PUT') {
        if (item.deletedAt) throw new HttpError(409, 'Сначала восстановите удалённую запись.');
        const body = await readBody(req);
        return send(200, expand(kind, transaction(rows => save(rows, kind, body, id))));
      }
      if (parts.length === 3 && req.method === 'DELETE') {
        if (url.searchParams.get('hard') === 'true') {
          transaction(rows => {
            checkDeletion(rows, kind, id);
            rows[kind] = rows[kind].filter(other => other.id !== id);
            if (kind === 'suppliers') rows.licenses = rows.licenses.filter(l => l.supplierId !== id);
          });
          return send(204);
        }
        return send(200, expand(kind, transaction(rows => softDelete(rows, kind, id))));
      }
      if (parts[3] === 'restore' && parts.length === 4 && req.method === 'POST') {
        const restored = transaction(rows => {
          const target = lookup(rows, kind, id);
          try { validate(rows, kind, target, id); }
          catch (error) { if (error.status === 422) throw new HttpError(409, 'Нельзя восстановить запись: проверьте связанные записи.'); throw error; }
          target.deletedAt = null;
          if (kind === 'suppliers') rows.licenses.filter(l => l.supplierId === id).forEach(l => { l.deletedAt = null; });
          return target;
        });
        return send(200, expand(kind, restored));
      }
      if (kind === 'drugs' && parts[3] === 'dispense' && parts.length === 4 && req.method === 'POST') {
        const body = await readBody(req);
        if (!Number.isInteger(body.quantity) || body.quantity <= 0 || body.quantity > 1000000) {
          invalid({ quantity: 'Количество должно быть целым числом от 1 до 1000000' });
        }
        const dispensed = transaction(rows => {
          const drug = lookup(rows, kind, id);
          if (drug.deletedAt) throw new HttpError(409, 'Удалённый препарат нельзя отпустить.');
          if (drug.stock < body.quantity) throw new HttpError(409, `Недостаточно упаковок. Доступно: ${drug.stock}, запрошено: ${body.quantity}.`);
          drug.stock -= body.quantity;
          return drug;
        });
        return send(200, expand(kind, dispensed));
      }
      throw new HttpError(405, 'Метод или операция не поддерживается.');
    } catch (error) {
      if (res.destroyed) return;
      if (!(error instanceof HttpError)) logger?.(error.stack);
      send(error.status ?? 500, { message: error.status ? error.message : 'Ошибка учебного сервера.',
        ...(error.errors ? { errors: error.errors } : {}) });
    }
  });
  return server;
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const option = (name, fallback) => {
    const index = args.indexOf(name);
    return index < 0 ? fallback : args[index + 1];
  };
  const port = Number(option('--port', '8080'));
  const origin = option('--origin', 'http://localhost:5555');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Неверный --port');
  const dataFile = args.includes('--no-persist') ? null :
    path.resolve(option('--data-file', path.join(__dirname, '.mock-data', 'catalog.v1.json')));
  const server = createMockServer({ origin, dataFile });
  server.on('error', error => { console.error(`Не удалось запустить сервер: ${error.message}`); process.exitCode = 1; });
  server.listen(port, option('--host', '127.0.0.1'), () => {
    console.log(`API: http://localhost:${port}/api; разрешённый Origin: ${origin}`);
    console.log(`Проверка: http://localhost:${port}/api/__health`);
    console.log(dataFile ? `Данные: ${dataFile}` : 'Данные только на время запуска.');
  });
}

module.exports = { createMockServer };
