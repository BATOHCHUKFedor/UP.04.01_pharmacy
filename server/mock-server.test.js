'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createMockServer } = require('../mock-server');
const seed = require('./seed-data.json');

async function start(t, options = {}) {
  const server = createMockServer({ logger: null, ...options });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}/api`;
  return async (route, method = 'GET', body, headers = {}) => {
    const response = await fetch(base + route, { method, headers: { 'Content-Type': 'application/json', ...headers },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, headers: response.headers,
      body: response.status === 204 ? null : await response.json() };
  };
}

test('health, серверная пагинация, поиск, фильтры и сортировка', async t => {
  const api = await start(t);
  assert.equal((await api('/__health')).body.status, 'ok');
  const first = (await api('/drugs?sort=id,asc&page=1&size=10')).body;
  const second = (await api('/drugs?sort=id,asc&page=2&size=10')).body;
  assert.equal(first.total, 24);
  assert.equal(first.items.length, 10);
  assert.equal(second.items[0].id, 11);
  const filtered = (await api('/drugs?search=Парацетамол&categoryId=1&manufacturerId=1&supplierId=1&yearFrom=2020&yearTo=2020')).body;
  assert.equal(filtered.total, 1);
  assert.equal(filtered.items[0].manufacturer.id, 1);
  assert.equal(filtered.items[0].categories[0].id, 1);
  assert.equal((await api('/drugs?search=невозможный-запрос')).body.total, 0);
});

test('422 сообщает дубликат регистрационного номера и почты', async t => {
  const api = await start(t);
  const drug = await api('/drugs', 'POST', seed.drugs[0]);
  assert.equal(drug.status, 422);
  assert.ok(drug.body.errors.registrationNumber);
  const supplier = await api('/suppliers', 'POST', seed.suppliers[0]);
  assert.equal(supplier.status, 422);
  assert.ok(supplier.body.errors.email);
  const invalid = await api('/categories', 'POST', { name: '', description: '' });
  assert.deepEqual(Object.keys(invalid.body.errors).sort(), ['description', 'name']);
});

test('409: связанный производитель и препарат с нулевым остатком', async t => {
  const api = await start(t);
  const deletion = await api('/manufacturers/1', 'DELETE');
  assert.equal(deletion.status, 409);
  assert.match(deletion.body.message, /4/);
  const dispense = await api('/drugs/1/dispense', 'POST', { quantity: 1 });
  assert.equal(dispense.status, 409);
  assert.match(dispense.body.message, /Доступно: 0/);
  const stock = seed.drugs[1].stock;
  assert.equal((await api('/drugs/2/dispense', 'POST', { quantity: stock })).body.stock, 0);
});

test('полный CRUD для пяти сущностей, массовое удаление и каскад лицензии', async t => {
  const api = await start(t);
  const m = (await api('/manufacturers', 'POST', { name: 'Завод', country: 'Россия', contactEmail: 'm@test.ru' })).body;
  const c = (await api('/categories', 'POST', { name: 'Группа', description: 'Описание' })).body;
  const supplierInput = { name: 'Поставщик', contactPerson: 'Контакт', country: 'Россия', phone: '123',
    email: 'unique@test.ru', partnershipYear: 2025, manufacturerIds: [m.id] };
  const s = (await api('/suppliers', 'POST', supplierInput)).body;
  const l = (await api('/licenses', 'POST', { supplierId: s.id, number: 'ЛИЦ', issuedYear: 2025, expiresYear: 2035 })).body;
  const drugInput = { name: 'Препарат', registrationNumber: 'ТЕСТ', manufacturerId: m.id, supplierId: s.id,
    categoryIds: [c.id], productionYear: 2025, price: 50, stock: 5 };
  const d = (await api('/drugs', 'POST', drugInput)).body;
  const pairs = [['drugs', d.id, { ...drugInput, name: 'Обновлён' }],
    ['licenses', l.id, { supplierId: s.id, number: 'ЛИЦ-2', issuedYear: 2025, expiresYear: 2035 }],
    ['suppliers', s.id, { ...supplierInput, name: 'Обновлён' }],
    ['categories', c.id, { name: 'Обновлена', description: 'Описание' }],
    ['manufacturers', m.id, { name: 'Обновлён', country: 'Россия', contactEmail: 'm@test.ru' }]];
  for (const [kind, id, input] of pairs) {
    assert.equal((await api(`/${kind}/${id}`, 'GET')).status, 200);
    assert.equal((await api(`/${kind}/${id}`, 'PUT', input)).status, 200);
  }
  const bulk = await api('/drugs/bulk-delete', 'POST', { ids: [d.id, d.id] });
  assert.equal(bulk.body.deleted, 1);
  assert.ok((await api(`/drugs/${d.id}`)).body.deletedAt);
  assert.equal((await api(`/drugs/${d.id}/restore`, 'POST')).body.deletedAt, null);
  for (const [kind, id] of pairs) {
    assert.equal((await api(`/${kind}/${id}`, 'DELETE')).status, 200);
    assert.equal((await api(`/${kind}/${id}/restore`, 'POST')).status, 200);
    assert.equal((await api(`/${kind}/${id}?hard=true`, 'DELETE')).status, 204);
    assert.equal((await api(`/${kind}/${id}`)).status, 404);
  }
  const nested = await api('/suppliers', 'POST', { ...supplierInput, email: 'nested@test.ru', manufacturerIds: [1],
    license: { number: 'ВЛОЖЕННАЯ', issuedYear: 2025, expiresYear: 2035 } });
  assert.equal(nested.status, 201);
  const nestedId = nested.body.id;
  const licenseId = nested.body.license.id;
  await api(`/suppliers/${nestedId}`, 'DELETE');
  assert.ok((await api(`/licenses/${licenseId}`)).body.deletedAt);
  await api(`/suppliers/${nestedId}/restore`, 'POST');
  assert.equal((await api(`/licenses/${licenseId}`)).body.deletedAt, null);
  await api(`/suppliers/${nestedId}?hard=true`, 'DELETE');
  assert.equal((await api(`/licenses/${licenseId}`)).status, 404);
});

test('отказ в массовом удалении атомарен', async t => {
  const api = await start(t);
  const unused = (await api('/categories', 'POST', { name: 'Свободная', description: 'Описание' })).body;
  assert.equal((await api('/categories/bulk-delete', 'POST', { ids: [unused.id, 1] })).status, 409);
  assert.equal((await api(`/categories/${unused.id}`)).body.deletedAt, null);
});

test('принудительный 500 и заметная задержка 1500 мс', async t => {
  const api = await start(t);
  assert.equal((await api('/drugs?__fail=500')).status, 500);
  const before = Date.now();
  assert.equal((await api('/drugs?__delay=1500')).status, 200);
  assert.ok(Date.now() - before >= 1450);
});

test('CORS: preflight разрешён, чужой Origin отклоняется', async t => {
  const api = await start(t);
  const preflight = await api('/drugs', 'OPTIONS', undefined, { Origin: 'http://localhost:5555' });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'http://localhost:5555');
  const mismatch = await api('/drugs', 'GET', undefined, { Origin: 'http://localhost:5000' });
  assert.equal(mismatch.status, 403);
  assert.notEqual(mismatch.headers.get('access-control-allow-origin'), 'http://localhost:5000');
});

test('изменения сохраняются между экземплярами сервера', async t => {
  const tempRoot = path.resolve(os.tmpdir());
  const dir = fs.mkdtempSync(path.join(tempRoot, 'pharmacy-api-test-'));
  const dataFile = path.join(dir, 'catalog.json');
  const first = await start(t, { dataFile });
  const created = (await first('/categories', 'POST', { name: 'Сохранённая', description: 'Описание' })).body;
  const second = await start(t, { dataFile });
  t.after(() => {
    const resolved = path.resolve(dir);
    assert.equal(path.dirname(resolved), tempRoot);
    assert.ok(path.basename(resolved).startsWith('pharmacy-api-test-'));
    fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });
  assert.equal((await second(`/categories/${created.id}`)).body.name, 'Сохранённая');
  assert.equal((await second(`/categories/${created.id}?hard=true`, 'DELETE')).status, 204);
  const third = await start(t, { dataFile });
  assert.equal((await third(`/categories/${created.id}`)).status, 404);
  const next = (await third('/categories', 'POST', { name: 'Следующая', description: 'Описание' })).body;
  assert.ok(next.id > created.id, 'Удалённый идентификатор не переиспользуется');
});
