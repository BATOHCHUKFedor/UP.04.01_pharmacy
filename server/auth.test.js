'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createMockServer } = require('../mock-server');

async function setup(t, options = {}) {
  const server = createMockServer({ logger: null, ...options });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}/api`;
  const api = async (route, { method = 'GET', body, token } = {}) => {
    const response = await fetch(base + route, { method, headers: {
      'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}),
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, body: response.status === 204 ? null : await response.json() };
  };
  const login = async (username, password = { customer: 'Customer123!', pharmacist: 'Pharmacist123!', admin: 'Admin123!' }[username]) => {
    const result = await api('/auth/login', { method: 'POST', body: { username, password } });
    assert.equal(result.status, 200);
    return result.body;
  };
  return { api, login };
}

test('защищённый каталог требует токен; health и preflight остаются публичными', async t => {
  const { api } = await setup(t);
  assert.equal((await api('/drugs')).status, 401);
  assert.equal((await api('/__health')).status, 200);
  assert.equal((await api('/drugs', { method: 'OPTIONS' })).status, 204);
});

test('вход: обязательные поля, неверный пароль, отсутствие хеша в ответе', async t => {
  const { api, login } = await setup(t);
  assert.equal((await api('/auth/login', { method: 'POST', body: {} })).status, 422);
  const bad = await api('/auth/login', { method: 'POST', body: { username: 'admin', password: 'bad' } });
  assert.equal(bad.status, 401); assert.match(bad.body.message, /Неверный/);
  const valid = await login('admin');
  assert.equal(valid.user.password, undefined);
  assert.equal(valid.user.role, 'admin');
  assert.ok(valid.refreshToken && valid.accessToken && valid.session.id);
});

test('регистрация проверяет пароль и уникальность, не разрешает присвоить admin', async t => {
  const { api } = await setup(t);
  const input = { username: 'new-user', name: 'Новый пользователь', password: 'Strong123!', role: 'admin' };
  for (const password of ['short1!', 'withoutdigit!', 'withoutSpecial123']) {
    const invalid = await api('/auth/register', { method: 'POST', body: { ...input, password } });
    assert.equal(invalid.status, 422); assert.ok(invalid.body.errors.password);
  }
  const valid = await api('/auth/register', { method: 'POST', body: input });
  assert.equal(valid.status, 201); assert.equal(valid.body.user.role, 'customer');
  const duplicate = await api('/auth/register', { method: 'POST', body: input });
  assert.equal(duplicate.status, 422); assert.ok(duplicate.body.errors.username);
});

test('три роли: каталог и уникальные разделы проверяются сервером, не иерархически', async t => {
  const { api, login } = await setup(t);
  const matrix = {
    customer: [200, 200, 403, 403, 403, 403],
    pharmacist: [200, 403, 200, 200, 403, 403],
    admin: [200, 403, 403, 403, 200, 200],
  };
  for (const [role, expected] of Object.entries(matrix)) {
    const { accessToken: token } = await login(role);
    for (const [i, route] of ['/drugs', '/reservations/mine', '/reservations', '/customers', '/admin/users', '/admin/statistics'].entries()) {
      assert.equal((await api(route, { token })).status, expected[i], `${role}: ${route}`);
    }
  }
});

test('подмена роли в профиле не даёт права удаления; подмена JWT отвергается', async t => {
  const { api, login } = await setup(t);
  const session = await login('customer');
  session.user.role = 'admin'; // Как изменение JSON профиля в localStorage.
  assert.equal((await api('/drugs/2?hard=true', { method: 'DELETE', token: session.accessToken })).status, 403);
  assert.equal((await api('/drugs/2', { token: session.accessToken })).status, 200);
  const parts = session.accessToken.split('.');
  const claims = JSON.parse(Buffer.from(parts[1], 'base64url')); claims.role = 'admin';
  parts[1] = Buffer.from(JSON.stringify(claims)).toString('base64url');
  assert.equal((await api('/drugs', { token: parts.join('.') })).status, 401);
});

test('только admin физически удаляет и восстанавливает; pharmacist отпускает', async t => {
  const { api, login } = await setup(t);
  const p = (await login('pharmacist')).accessToken;
  const a = (await login('admin')).accessToken;
  assert.equal((await api('/drugs/2?hard=true', { method: 'DELETE', token: p })).status, 403);
  assert.equal((await api('/drugs/2', { method: 'DELETE', token: p })).status, 200);
  assert.equal((await api('/drugs/2/restore', { method: 'POST', token: p })).status, 403);
  assert.equal((await api('/drugs/2/restore', { method: 'POST', token: a })).status, 200);
  assert.equal((await api('/drugs/2/dispense', { method: 'POST', token: a, body: { quantity: 1 } })).status, 403);
  assert.equal((await api('/drugs/2/dispense', { method: 'POST', token: p, body: { quantity: 1 } })).status, 200);
});

test('истёкший access: refresh выдаёт новую пару, прежний refresh не используется повторно', async t => {
  let time = 1800000000000;
  const { api, login } = await setup(t, { ttl: 60, now: () => time });
  const old = await login('customer'); time += 61000;
  assert.equal((await api('/drugs', { token: old.accessToken })).status, 401);
  const next = await api('/auth/refresh', { method: 'POST', body: { refreshToken: old.refreshToken } });
  assert.equal(next.status, 200);
  assert.equal(next.body.session.startedAt, old.session.startedAt);
  assert.equal(next.body.session.expiresAt, old.session.expiresAt);
  assert.equal((await api('/drugs', { token: next.body.accessToken })).status, 200);
  assert.equal((await api('/auth/refresh', { method: 'POST', body: { refreshToken: old.refreshToken } })).status, 401);
});

test('выход отзывает серверную сессию: даже сохранённые токены больше не работают', async t => {
  const { api, login } = await setup(t);
  const session = await login('customer');
  assert.equal((await api('/auth/logout', { method: 'POST', body: { refreshToken: session.refreshToken } })).status, 204);
  assert.equal((await api('/drugs', { token: session.accessToken })).status, 401);
  assert.equal((await api('/auth/refresh', { method: 'POST', body: { refreshToken: session.refreshToken } })).status, 401);
});

test('выход во время refresh отзывает сессию даже по прежнему refresh', async t => {
  const { api, login } = await setup(t);
  const old = await login('customer');
  const next = await api('/auth/refresh', { method: 'POST', body: { refreshToken: old.refreshToken } });
  assert.equal(next.status, 200);
  await api('/auth/logout', { method: 'POST', body: { refreshToken: old.refreshToken } });
  assert.equal((await api('/drugs', { token: next.body.accessToken })).status, 401);
});

test('бездействие и абсолютный срок серверной сессии не обходятся обновлением токена', async t => {
  let time = 1800000000000;
  const { api, login } = await setup(t, { ttl: 900, sessionTtl: 300, idleTtl: 180, now: () => time });
  const idle = await login('customer'); time += 180000;
  assert.equal((await api('/auth/refresh', { method: 'POST', body: { refreshToken: idle.refreshToken } })).status, 401);
  const active = await login('customer');
  for (let i = 0; i < 2; i++) {
    time += 100000;
    assert.equal((await api('/auth/activity', { method: 'POST', token: active.accessToken })).status, 200);
  }
  time += 100000;
  assert.equal((await api('/auth/refresh', { method: 'POST', body: { refreshToken: active.refreshToken } })).status, 401);
});

test('бронирование: резерв остатков, продление только владельцем, возврат при отмене', async t => {
  const { api, login } = await setup(t);
  const p = (await login('pharmacist')).accessToken;
  const c = (await login('customer')).accessToken;
  const other = await api('/auth/register', { method: 'POST', body: { username: 'other', name: 'Другой пользователь', password: 'Other123!' } });
  const stock = (await api('/drugs/2', { token: p })).body.stock;
  const created = await api('/reservations', { method: 'POST', token: p, body: { drugId: 2, userId: 1, quantity: 2 } });
  assert.equal(created.status, 201);
  const id = created.body.id;
  assert.equal((await api('/drugs/2', { token: p })).body.stock, stock - 2);
  assert.equal((await api(`/reservations/${id}/extend`, { method: 'POST', token: other.body.accessToken })).status, 403);
  assert.equal((await api(`/reservations/${id}/extend`, { method: 'POST', token: c })).status, 200);
  assert.equal((await api(`/reservations/${id}/extend`, { method: 'POST', token: c })).status, 409);
  assert.equal((await api('/drugs/2', { method: 'DELETE', token: p })).status, 409);
  assert.equal((await api(`/reservations/${id}/cancel`, { method: 'POST', token: p })).status, 200);
  assert.equal((await api('/drugs/2', { token: p })).body.stock, stock);
  assert.equal((await api(`/reservations/${id}/cancel`, { method: 'POST', token: p })).status, 409);
});

test('admin меняет права; старые сессии отзываются; последний admin защищён', async t => {
  const { api, login } = await setup(t);
  const a = (await login('admin')).accessToken;
  const c = (await login('customer')).accessToken;
  assert.equal((await api('/admin/users/3', { method: 'PUT', token: a, body: { role: 'customer' } })).status, 409);
  assert.equal((await api('/admin/users/1', { method: 'PUT', token: a, body: { role: 'pharmacist' } })).status, 200);
  assert.equal((await api('/drugs', { token: c })).status, 401);
  const changed = await login('customer');
  assert.equal(changed.user.role, 'pharmacist');
  assert.equal((await api('/customers', { token: changed.accessToken })).status, 200);
});

test('сервер сохраняет аккаунты, секрет подписи и сессии между запусками', async t => {
  const root = path.resolve(os.tmpdir());
  const dir = fs.mkdtempSync(path.join(root, 'pharmacy-auth-test-'));
  const dataFile = path.join(dir, 'catalog.json');
  const first = await setup(t, { dataFile });
  const result = await first.api('/auth/register', { method: 'POST', body: { username: 'persistent', name: 'Сохранённый', password: 'Persist123!' } });
  assert.equal(result.status, 201);
  const second = await setup(t, { dataFile });
  t.after(() => {
    assert.equal(path.dirname(path.resolve(dir)), root);
    assert.ok(path.basename(dir).startsWith('pharmacy-auth-test-'));
    fs.rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });
  const me = await second.api('/auth/me', { token: result.body.accessToken });
  assert.equal(me.status, 200); assert.equal(me.body.user.username, 'persistent');
  const renewed = await second.api('/auth/refresh', { method: 'POST', body: { refreshToken: result.body.refreshToken } });
  assert.equal(renewed.status, 200);
});
