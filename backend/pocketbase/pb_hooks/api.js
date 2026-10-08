'use strict';
const c = require(__hooks + '/core.js');
const auth = require(__hooks + '/auth.js');
const catalog = require(__hooks + '/catalog.js');
const accounts = require(__hooks + '/accounts.js');

function dispatch(e, app, parts, method, body, q) {
  const result = (value, status = 200) => ({ status, body: value });
  if (parts[0] === '__health' && parts.length === 1 && method === 'GET')
    return result({ ok: true, backend: 'pocketbase', schemaVersion: 1 });
  if (parts[0] === 'auth') {
    if (parts.length !== 2) c.fail(404, 'Адрес авторизации не найден.');
    const action = parts[1];
    if (method === 'POST' && action === 'login') return result(auth.login(app, body));
    if (method === 'POST' && action === 'register') {
      auth.addUser(app, body, 'customer'); return result(auth.login(app, body), 201);
    }
    if (method === 'POST' && action === 'refresh') return result(auth.refresh(app, body));
    if (method === 'POST' && action === 'logout') { auth.logout(app, body); return result(null, 204); }
    const actor = auth.authenticate(app, e);
    if (method === 'GET' && action === 'me') return result({ user: auth.userDto(actor.user), session: auth.sessionDto(actor.session) });
    if (method === 'POST' && action === 'activity') {
      auth.live(app, actor.session); actor.session.set('lastActivity', Date.now()); app.save(actor.session);
      return result(auth.sessionDto(actor.session));
    }
    c.fail(405, 'Операция авторизации не поддерживается.');
  }
  const actor = auth.authenticate(app, e);
  const accountResult = accounts.dispatch(app, parts, method, body, actor);
  if (accountResult) return accountResult;
  if (parts[0] === 'references' && parts.length === 1 && method === 'GET') {
    auth.permission(actor.user, 'catalog.read');
    const values = {};
    c.kinds.filter(kind => kind !== 'drugs').forEach(kind => {
      values[kind] = c.rows(app, kind).map(row => c.dto(app, kind, row));
    });
    return result(values);
  }
  const kind = parts[0];
  if (!c.kinds.includes(kind)) c.fail(404, 'Раздел не найден.');
  auth.permission(actor.user, 'catalog.read');
  if (actor.user.getString('role') === 'customer' && (kind !== 'drugs' || q.includeDeleted === 'true'))
    c.fail(403, 'Этот раздел недоступен пользователю.');
  if (parts.length === 1 && method === 'GET') return result(catalog.list(app, kind, q));
  if (parts.length === 1 && method === 'POST') {
    auth.permission(actor.user, 'catalog.write'); return result(c.dto(app, kind, catalog.save(app, kind, body)), 201);
  }
  if (parts.length === 2 && parts[1] === 'bulk-delete' && method === 'POST') {
    auth.permission(actor.user, 'catalog.delete');
    if (!Array.isArray(body.ids) || body.ids.length > 1000 || body.ids.some(id => !Number.isInteger(id) || id <= 0))
      c.invalid({ ids: 'Выберите до 1000 записей с положительными целыми кодами' });
    const changed = [];
    Array.from(new Set(body.ids)).forEach(code => {
      const row = c.byCode(app, kind, code, false);
      if (c.active(row)) changed.push(catalog.remove(app, kind, row));
    });
    const licenseIds = kind === 'suppliers' ? changed.map(row => row.id) : [];
    return result({ deleted: changed.length, items: changed.map(row => c.dto(app, kind, row)),
      licenses: licenseIds.length ? c.rows(app, 'licenses').filter(row => licenseIds.includes(row.getString('supplier')))
        .map(row => c.dto(app, 'licenses', row)) : [] });
  }
  const code = Number(parts[1]);
  if (!Number.isInteger(code) || code <= 0) c.fail(404, 'Некорректный код записи.');
  const row = c.byCode(app, kind, code);
  if (actor.user.getString('role') === 'customer' && !c.active(row)) c.fail(403, 'Удалённая запись недоступна.');
  if (parts.length === 2 && method === 'GET') return result(c.dto(app, kind, row));
  if (parts.length === 2 && method === 'PUT') {
    auth.permission(actor.user, 'catalog.write'); return result(c.dto(app, kind, catalog.save(app, kind, body, code)));
  }
  if (parts.length === 2 && method === 'DELETE') {
    const hard = q.hard === 'true'; auth.permission(actor.user, hard ? 'catalog.hardDelete' : 'catalog.delete');
    const changed = catalog.remove(app, kind, row, hard);
    return result(hard ? null : c.dto(app, kind, changed), hard ? 204 : 200);
  }
  if (parts.length === 3 && parts[2] === 'restore' && method === 'POST') {
    auth.permission(actor.user, 'catalog.restore'); return result(c.dto(app, kind, catalog.restore(app, kind, row)));
  }
  if (kind === 'drugs' && parts.length === 3 && parts[2] === 'dispense' && method === 'POST') {
    auth.permission(actor.user, 'dispense');
    if (!c.active(row)) c.fail(409, 'Удалённый препарат нельзя отпустить.');
    if (!Number.isInteger(body.quantity) || body.quantity < 1 || body.quantity > 1000000)
      c.invalid({ quantity: 'Количество: целое число от 1 до 1000000' });
    if (row.getInt('stock') < body.quantity) c.fail(409, 'Недостаточно упаковок. Доступно: ' + row.getInt('stock') + '.');
    row.set('stock', row.getInt('stock') - body.quantity); app.save(row); return result(c.dto(app, kind, row));
  }
  c.fail(405, 'Операция не поддерживается.');
}

function handle(e) {
  const method = e.request.method, parts = e.request.pathValue('path').split('/').filter(Boolean);
  let response, failure;
  try {
    let info;
    try { info = e.requestInfo(); } catch (_) { c.fail(400, 'Некорректный JSON запроса.'); }
    const q = info.query || {};
    const body = info.body || {};
    if (Array.isArray(body) || typeof body !== 'object') c.fail(400, 'Ожидается JSON-объект.');
    // Diagnostics are deliberately opt-in; they must not slow arbitrary public requests.
    if ($os.getenv('PHARMACY_DEBUG_API') === '1' && c.kinds.includes(parts[0])) {
      const delay = Math.min(30000, Math.max(0, Number(q.__delay) || 0)); if (delay) sleep(delay);
      if (q.__fail) c.fail(Number(q.__fail) >= 400 && Number(q.__fail) <= 599 ? Number(q.__fail) : 500, 'Учебная ошибка сервера.');
    }
    if (method === 'GET') response = dispatch(e, e.app, parts, method, body, q);
    else {
      // Preserve field/status information across Go callback boundaries and roll back all writes.
      try {
        e.app.runInTransaction(tx => {
          try { response = dispatch(e, tx, parts, method, body, q); }
          catch (error) { failure = error; throw error; }
        });
      } catch (error) { throw failure || error; }
    }
    if (response.status === 204) return e.noContent(204);
    return e.json(response.status, response.body);
  } catch (error) {
    if (!error.status) console.error('Pharmacy API: ' + String(error));
    return e.json(error.status || 500, { message: error.status ? error.message : 'Внутренняя ошибка сервера.',
      ...(error.errors ? { errors: error.errors } : {}) });
  }
}
module.exports = { handle };
