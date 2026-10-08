'use strict';
// Real PocketBase integration tests. Never use the user's pb_data directory.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const pbRoot = path.resolve(__dirname, '..');
const executable = process.env.POCKETBASE_BIN || path.join(pbRoot, process.platform === 'win32' ? 'pocketbase.exe' : 'pocketbase');
const password = 'Fixture123!' + crypto.randomBytes(12).toString('hex');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

async function fixture(env = {}, directory) {
  const dir = directory || fs.mkdtempSync(path.join(os.tmpdir(), 'pharmacy-pb-test-'));
  const listener = net.createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const flags = ['--dir', dir, '--hooksDir', path.join(pbRoot, 'pb_hooks'), '--migrationsDir', path.join(pbRoot, 'pb_migrations')];
  if (!directory) {
    const create = spawnSync(executable, ['superuser', 'create', 'fixture@example.test', password, ...flags],
      { encoding: 'utf8', windowsHide: true, timeout: 30000 });
    if (create.error || create.status !== 0) throw new Error('Cannot prepare isolated PocketBase: ' + (create.error || create.stderr || create.stdout));
  }
  const child = spawn(executable, ['serve', '--http', '127.0.0.1:' + port, ...flags], {
    windowsHide: true, env: { ...process.env, PHARMACY_DEBUG_API: '1', ...env }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let logs = '', launchError;
  const exited = new Promise(resolve => { child.once('exit', resolve); child.once('error', error => { launchError = error; resolve(); }); });
  child.stdout.on('data', chunk => { logs += chunk; }); child.stderr.on('data', chunk => { logs += chunk; });
  const base = 'http://127.0.0.1:' + port;
  const send = async (route, method = 'GET', body, token, native = false) => {
    const response = await fetch(base + (native ? '/api' : '/api/pharmacy') + route, {
      method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: native ? token : 'Bearer ' + token } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(10000),
    });
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
  };
  const stop = async () => { if (child.exitCode === null && !launchError) child.kill(); await exited; };
  let ready = false;
  for (let attempt = 0; attempt < 150; attempt++) {
    if (launchError || child.exitCode !== null) break;
    try { const response = await send('/__health'); if (response.status === 200) { ready = true; break; } } catch (_) {}
    await wait(100);
  }
  if (!ready) { await stop(); if (!directory) cleanup(dir); throw new Error('PocketBase failed to start: ' + (launchError || logs)); }
  const superLogin = await send('/collections/_superusers/auth-with-password', 'POST',
    { identity: 'fixture@example.test', password }, undefined, true);
  assert.equal(superLogin.status, 200, JSON.stringify(superLogin.body));
  const superToken = superLogin.body.token;
  const register = async (username, role = 'customer') => {
    const registered = await send('/auth/register', 'POST', { username, name: 'Test ' + username, password, role });
    assert.equal(registered.status, 201, JSON.stringify(registered.body) + logs);
    assert.equal(registered.body.user.role, 'customer');
    if (role !== 'customer') {
      const list = await send('/collections/pharmacy_users/records?filter=' + encodeURIComponent('code = ' + registered.body.user.id),
        'GET', undefined, superToken, true);
      const row = list.body.items[0];
      const change = await send('/collections/pharmacy_users/records/' + row.id, 'PATCH', { role }, superToken, true);
      assert.equal(change.status, 200, JSON.stringify(change.body));
    }
    const login = await send('/auth/login', 'POST', { username, password });
    assert.equal(login.status, 200, JSON.stringify(login.body));
    return login.body;
  };
  return { dir, base, send, register, stop, logs: () => logs, superToken };
}
function cleanup(dir) {
  const resolved = path.resolve(dir), parent = path.resolve(os.tmpdir());
  if (path.dirname(resolved) !== parent || !path.basename(resolved).startsWith('pharmacy-pb-test-'))
    throw new Error('Refusing to remove a non-fixture directory');
  fs.rmSync(resolved, { recursive: true, force: true });
}
let pb, admin, pharmacist, customer;
const api = (route, method = 'GET', body, session = admin) => pb.send(route, method, body, session.accessToken);
const input = item => ({ ...item, manufacturerId: item.manufacturer?.id, supplierId: item.supplier?.id || item.supplierId,
  categoryIds: item.categories?.map(value => value.id), manufacturerIds: item.manufacturers?.map(value => value.id) });
before(async () => {
  pb = await fixture();
  try {
    admin = await pb.register('admin', 'admin'); pharmacist = await pb.register('pharmacist', 'pharmacist');
    customer = await pb.register('customer');
  } catch (error) { await pb.stop(); cleanup(pb.dir); throw error; }
});
after(async () => { if (pb) { await pb.stop(); cleanup(pb.dir); } });

test('PocketBase: public health and protected native collection API', async () => {
  assert.equal((await pb.send('/__health')).body.backend, 'pocketbase');
  assert.equal((await pb.send('/drugs')).status, 401);
  const native = await pb.send('/collections/drugs/records', 'GET', undefined, customer.accessToken, true);
  assert.notEqual(native.status, 200);
  const privateNative = await pb.send('/collections/pharmacy_config/records', 'GET', undefined, customer.accessToken, true);
  assert.notEqual(privateNative.status, 200);
});
test('PocketBase: login errors, mandatory fields and uniqueness of usernames', async () => {
  assert.equal((await pb.send('/auth/login', 'POST', { username: 'admin', password: 'Wrong123!' })).status, 401);
  const missing = await pb.send('/auth/register', 'POST', {});
  assert.equal(missing.status, 422); assert.ok(missing.body.errors.username); assert.ok(missing.body.errors.password);
  const duplicate = await pb.send('/auth/register', 'POST', { username: 'ADMIN', name: 'Duplicate', password });
  assert.equal(duplicate.status, 422); assert.ok(duplicate.body.errors.username);
  const unicodeWithoutSpecial = await pb.send('/auth/register', 'POST',
    { username: 'unicodepassword', name: 'Unicode Password', password: 'Password123漢字' });
  assert.equal(unicodeWithoutSpecial.status, 422); assert.ok(unicodeWithoutSpecial.body.errors.password);
  const longPassword = '漢'.repeat(125) + '1!?';
  const valid = await pb.send('/auth/register', 'POST', { username: 'longpassword', name: 'Long Password', password: longPassword });
  assert.equal(valid.status, 201, JSON.stringify(valid.body) + pb.logs());
  assert.equal((await pb.send('/auth/login', 'POST', { username: 'longpassword', password: longPassword })).status, 200);
  assert.equal((await pb.send('/auth/register', 'POST',
    { username: 'toolongpassword', name: 'Long Password', password: longPassword + 'x' })).status, 422);
});
test('PocketBase: SQL pagination, Unicode search, combined filters and empty result', async () => {
  const first = await api('/drugs?page=1&size=10&sort=id,asc');
  const second = await api('/drugs?page=2&size=10&sort=id,asc');
  assert.equal(first.status, 200, JSON.stringify(first.body)); assert.equal(second.status, 200, JSON.stringify(second.body));
  assert.equal(first.body.items.length, 10); assert.equal(second.body.page, 2);
  assert.notEqual(first.body.items[0].id, second.body.items[0].id);
  assert.ok(first.body.total > 10);
  const russian = await api('/drugs?search=' + encodeURIComponent('ПАРАЦЕТАМОЛ'));
  assert.equal(russian.status, 200); assert.ok(russian.body.items.some(row => row.name === 'Парацетамол'));
  const record = first.body.items[1];
  const filtered = await api(`/drugs?manufacturerId=${record.manufacturer.id}&supplierId=${record.supplier.id}&categoryId=${record.categories[0].id}`);
  assert.ok(filtered.body.items.some(row => row.id === record.id));
  const empty = await api('/drugs?search=does-not-exist-xyz'); assert.equal(empty.body.total, 0); assert.deepEqual(empty.body.items, []);
  const injection = await api('/drugs?search=' + encodeURIComponent("' OR 1=1 --")); assert.equal(injection.body.total, 0);
  assert.equal((await api('/drugs?sort=__proto__,desc')).status, 200);
  assert.equal((await api('/drugs?sort=' + encodeURIComponent('name; DROP TABLE drugs; --,asc'))).status, 200);
});
test('PocketBase: reference DTOs retain actual many-to-many and 1:1 relations', async () => {
  const references = await api('/references', 'GET', undefined, customer);
  assert.equal(references.status, 200); assert.ok(references.body.categories.length);
  const supplier = references.body.suppliers[0];
  assert.ok(supplier.manufacturers.length); assert.equal(supplier.license.supplierId, supplier.id);
  const duplicate = await api('/licenses', 'POST', { supplierId: supplier.id, number: 'DUPLICATE', issuedYear: 2020, expiresYear: 2030 });
  assert.equal(duplicate.status, 422); assert.ok(duplicate.body.errors.supplierId);
});
test('PocketBase: duplicate registration number returns field error 422', async () => {
  const original = (await api('/drugs/1')).body;
  const duplicate = await api('/drugs', 'POST', input(original));
  assert.equal(duplicate.status, 422, JSON.stringify(duplicate.body)); assert.ok(duplicate.body.errors.registrationNumber);
});
test('PocketBase: invalid phone and duplicate supplier email are field errors', async () => {
  const supplier = (await api('/suppliers/1')).body;
  const badPhone = await api('/suppliers/1', 'PUT', { ...input(supplier), phone: 'not a phone' });
  assert.equal(badPhone.status, 422); assert.ok(badPhone.body.errors.phone);
  const duplicate = await api('/suppliers', 'POST', input(supplier));
  assert.equal(duplicate.status, 422); assert.ok(duplicate.body.errors.email);
});
test('PocketBase: role is checked on server, not in client profile or forged JWT', async () => {
  assert.equal((await api('/admin/users', 'GET', undefined, customer)).status, 403);
  assert.equal((await api('/customers', 'GET', undefined, admin)).status, 403);
  assert.equal((await api('/admin/statistics', 'GET', undefined, pharmacist)).status, 403);
  assert.equal((await api('/drugs/2?hard=true', 'DELETE', undefined, pharmacist)).status, 403);
  const parts = customer.accessToken.split('.');
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url')); payload.role = 'admin';
  parts[1] = Buffer.from(JSON.stringify(payload)).toString('base64url');
  assert.equal((await pb.send('/admin/users', 'GET', undefined, parts.join('.'))).status, 401);
  // Keeping the original valid token and forging just the cached profile still yields 403.
  const forgedProfile = { ...customer, user: { ...customer.user, role: 'admin' } };
  assert.equal((await api('/admin/users', 'GET', undefined, forgedProfile)).status, 403);
});
test('PocketBase: linked deletions are rejected even when child drugs are soft-deleted', async () => {
  const drug = (await api('/drugs/2')).body;
  assert.equal((await api('/drugs/2', 'DELETE')).status, 200);
  const denial = await api('/categories/' + drug.categories[0].id, 'DELETE');
  assert.equal(denial.status, 409); assert.match(denial.body.message, /связанных препаратов/);
  assert.equal((await api('/drugs/2/restore', 'POST')).status, 200);
});
test('PocketBase: stock shortage returns 409 without mutating stock', async () => {
  const original = (await api('/drugs/1')).body;
  const result = await api('/drugs/1/dispense', 'POST', { quantity: original.stock + 1 }, pharmacist);
  assert.equal(result.status, 409); assert.equal((await api('/drugs/1')).body.stock, original.stock);
});
test('PocketBase: nested invalid license rolls back supplier and sequence together', async () => {
  const count = (await api('/suppliers')).body.total;
  const result = await api('/suppliers', 'POST', { name: 'Rollback supplier', contactPerson: 'Test', country: 'Россия',
    phone: '+7 (999) 111-22-33', email: 'rollback@example.test', partnershipYear: 2020, manufacturerIds: [1],
    license: { number: '', issuedYear: 2020, expiresYear: 2030 } });
  assert.equal(result.status, 422, JSON.stringify(result.body)); assert.ok(result.body.errors.licenseNumber);
  assert.equal((await api('/suppliers')).body.total, count);
});
test('PocketBase: full CRUD for all five entities, supplier license cascade and bulk deletion', async () => {
  const manufacturerInput = { name: 'Fixture Manufacturer', country: 'Россия', contactEmail: 'manufacturer@example.test' };
  const categoryInput = { name: 'Fixture Category', description: 'For integration test' };
  const manufacturer = await api('/manufacturers', 'POST', manufacturerInput); assert.equal(manufacturer.status, 201);
  const category = await api('/categories', 'POST', categoryInput); assert.equal(category.status, 201);
  const supplierInput = { name: 'Fixture Supplier', country: 'Россия', contactPerson: 'Test Person',
    phone: '+79991112233', email: 'supplier@example.test', partnershipYear: 2020, manufacturerIds: [manufacturer.body.id],
    license: { number: 'FIXTURE-LICENSE', issuedYear: 2020, expiresYear: 2030 } };
  const supplier = await api('/suppliers', 'POST', supplierInput); assert.equal(supplier.status, 201, JSON.stringify(supplier.body));
  const license = supplier.body.license;
  const drugInput = { name: 'Fixture Drug', registrationNumber: 'FIXTURE-UNIQUE', manufacturerId: manufacturer.body.id,
    supplierId: supplier.body.id, categoryIds: [category.body.id], productionYear: 2020, price: 12.34, stock: 5 };
  const drug = await api('/drugs', 'POST', drugInput); assert.equal(drug.status, 201);
  for (const [kind, id, values] of [
    ['drugs', drug.body.id, { ...drugInput, price: 23.45 }],
    ['suppliers', supplier.body.id, { ...supplierInput, contactPerson: 'Changed Contact' }],
    ['manufacturers', manufacturer.body.id, { ...manufacturerInput, country: 'Германия' }],
    ['categories', category.body.id, { ...categoryInput, description: 'Changed description' }],
    ['licenses', license.id, { supplierId: supplier.body.id, number: 'CHANGED', issuedYear: 2021, expiresYear: 2031 }],
  ]) {
    assert.equal((await api(`/${kind}/${id}`)).status, 200);
    assert.equal((await api(`/${kind}/${id}`, 'PUT', values)).status, 200);
  }
  const atomic = await api('/manufacturers/bulk-delete', 'POST', { ids: [manufacturer.body.id, 1] });
  assert.equal(atomic.status, 409); assert.equal((await api('/manufacturers/' + manufacturer.body.id)).body.deletedAt, null);
  const independent = await api('/categories', 'POST', { name: 'Atomic free category', description: 'Eligible first record' });
  const rollback = await api('/categories/bulk-delete', 'POST', { ids: [independent.body.id, 1] });
  assert.equal(rollback.status, 409); assert.equal((await api('/categories/' + independent.body.id)).body.deletedAt, null);
  const bulk = await api('/drugs/bulk-delete', 'POST', { ids: [drug.body.id, drug.body.id] });
  assert.equal(bulk.body.deleted, 1); assert.equal((await api('/drugs/' + drug.body.id + '/restore', 'POST')).status, 200);
  assert.equal((await api('/drugs/' + drug.body.id + '?hard=true', 'DELETE')).status, 204);
  assert.equal((await api('/drugs/' + drug.body.id)).status, 404);
  assert.equal((await api('/licenses/' + license.id, 'DELETE')).status, 200);
  assert.equal((await api('/licenses/' + license.id + '/restore', 'POST')).status, 200);
  assert.equal((await api('/suppliers/' + supplier.body.id, 'DELETE')).status, 200);
  assert.ok((await api('/licenses/' + license.id)).body.deletedAt);
  assert.equal((await api('/suppliers/' + supplier.body.id + '/restore', 'POST')).status, 200);
  assert.equal((await api('/licenses/' + license.id)).body.deletedAt, null);
  assert.equal((await api('/licenses/' + license.id + '?hard=true', 'DELETE')).status, 204);
  assert.equal((await api('/suppliers/' + supplier.body.id + '?hard=true', 'DELETE')).status, 204);
  for (const [kind, id] of [['manufacturers', manufacturer.body.id], ['categories', category.body.id]]) {
    assert.equal((await api(`/${kind}/${id}`, 'DELETE')).status, 200);
    assert.equal((await api(`/${kind}/${id}/restore`, 'POST')).status, 200);
    assert.equal((await api(`/${kind}/${id}?hard=true`, 'DELETE')).status, 204);
  }
});
test('PocketBase: reservations, ownership check, extension and cancel restore stock atomically', async () => {
  const before = (await api('/drugs/3')).body.stock;
  const reservation = await api('/reservations', 'POST', { drugId: 3, userId: customer.user.id, quantity: 2 }, pharmacist);
  assert.equal(reservation.status, 201, JSON.stringify(reservation.body));
  assert.equal((await api('/drugs/3')).body.stock, before - 2);
  const other = await pb.register('othercustomer');
  assert.equal((await api('/reservations/' + reservation.body.id + '/extend', 'POST', {}, other)).status, 403);
  assert.equal((await api('/reservations/' + reservation.body.id + '/extend', 'POST', {}, customer)).status, 200);
  assert.equal((await api('/reservations/' + reservation.body.id + '/extend', 'POST', {}, customer)).status, 409);
  assert.equal((await api('/drugs/3', 'DELETE')).status, 409);
  assert.equal((await api('/reservations/' + reservation.body.id + '/cancel', 'POST', {}, pharmacist)).status, 200);
  assert.equal((await api('/drugs/3')).body.stock, before);
  assert.equal((await api('/reservations/' + reservation.body.id + '/cancel', 'POST', {}, pharmacist)).status, 409);
});
test('PocketBase: refresh rotation, replay denial and logout revokes access token', async () => {
  const session = await pb.register('rotation');
  const refreshed = await pb.send('/auth/refresh', 'POST', { refreshToken: session.refreshToken });
  assert.equal(refreshed.status, 200);
  assert.notEqual(refreshed.body.refreshToken, session.refreshToken);
  assert.equal((await pb.send('/auth/refresh', 'POST', { refreshToken: session.refreshToken })).status, 401);
  // Previous refresh may revoke an in-flight rotated session, but may not refresh it.
  assert.equal((await pb.send('/auth/logout', 'POST', { refreshToken: session.refreshToken })).status, 204);
  assert.equal((await pb.send('/auth/me', 'GET', undefined, refreshed.body.accessToken)).status, 401);
  assert.equal((await pb.send('/auth/refresh', 'POST', { refreshToken: refreshed.body.refreshToken })).status, 401);
});
test('PocketBase: server denies refresh after idle or absolute deadline', async () => {
  for (const field of ['lastActivity', 'expiresAt']) {
    const session = await pb.register('deadline_' + field.toLowerCase());
    const values = field === 'lastActivity' ? { lastActivity: Date.now() - 181000 } : { expiresAt: Date.now() - 1000 };
    const changed = await pb.send('/collections/pharmacy_sessions/records/' + session.session.id, 'PATCH', values, pb.superToken, true);
    assert.equal(changed.status, 200);
    assert.equal((await pb.send('/auth/me', 'GET', undefined, session.accessToken)).status, 401);
    assert.equal((await pb.send('/auth/refresh', 'POST', { refreshToken: session.refreshToken })).status, 401);
  }
});
test('PocketBase: changing rights revokes sessions and the last administrator is protected', async () => {
  const target = await pb.register('rights_target');
  const changed = await api('/admin/users/' + target.user.id, 'PUT', { role: 'pharmacist', active: true });
  assert.equal(changed.status, 200, JSON.stringify(changed.body) + pb.logs()); assert.equal(changed.body.role, 'pharmacist');
  assert.equal((await pb.send('/auth/me', 'GET', undefined, target.accessToken)).status, 401);
  assert.equal((await pb.send('/auth/refresh', 'POST', { refreshToken: target.refreshToken })).status, 401);
  assert.equal((await api('/admin/users/' + admin.user.id, 'PUT', { role: 'customer', active: true })).status, 409);
  assert.equal((await api('/admin/users/abc', 'PUT', { role: 'customer', active: true })).status, 404);
});
test('PocketBase: CORS preflight permits Authorization from the local client', async () => {
  const response = await fetch(pb.base + '/api/pharmacy/drugs', { method: 'OPTIONS', headers: {
    Origin: 'http://localhost:5555', 'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'authorization,content-type',
  } });
  assert.ok([200, 204].includes(response.status));
  assert.ok(['*', 'http://localhost:5555'].includes(response.headers.get('access-control-allow-origin')));
  assert.match(response.headers.get('access-control-allow-headers').toLowerCase(), /authorization/);
});
test('PocketBase: malformed JSON and non-object bodies are rejected without internal error', async () => {
  for (const body of ['{broken', '[]', 'true']) {
    const result = await fetch(pb.base + '/api/pharmacy/categories', { method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + admin.accessToken }, body });
    assert.equal(result.status, 400);
  }
});
test('PocketBase: simulated delay/500 and invalid filter range', async () => {
  assert.equal((await api('/drugs?__fail=500')).status, 500);
  const start = Date.now(); assert.equal((await api('/drugs?__delay=150')).status, 200);
  assert.ok(Date.now() - start >= 140);
  const bad = await api('/drugs?yearFrom=2050&yearTo=2000'); assert.equal(bad.status, 422); assert.ok(bad.body.errors.yearTo);
});
test('PocketBase: saved records and physical deletions survive server restart; counters never reuse deleted codes', async () => {
  const deleted = await api('/categories', 'POST', { name: 'Gone Forever', description: 'Physically deleted' });
  assert.equal(deleted.status, 201);
  assert.equal((await api('/categories/' + deleted.body.id + '?hard=true', 'DELETE')).status, 204);
  const dir = pb.dir; await pb.stop(); pb = await fixture({}, dir);
  assert.equal((await api('/categories/' + deleted.body.id)).status, 404);
  assert.equal((await api('/drugs/1')).status, 200); // token and session survive server restart
  const next = await api('/categories', 'POST', { name: 'New After Restart', description: 'Counter persisted' });
  assert.equal(next.status, 201); assert.ok(next.body.id > deleted.body.id);
});
test('PocketBase: expired access token can be refreshed using live persisted session', async () => {
  const short = await fixture({ PHARMACY_ACCESS_TTL: '1' });
  try {
    const session = await short.register('shortttl');
    await wait(1200);
    assert.equal((await short.send('/auth/me', 'GET', undefined, session.accessToken)).status, 401);
    const refreshed = await short.send('/auth/refresh', 'POST', { refreshToken: session.refreshToken });
    assert.equal(refreshed.status, 200);
    assert.equal((await short.send('/auth/me', 'GET', undefined, refreshed.body.accessToken)).status, 200);
  } finally { await short.stop(); cleanup(short.dir); }
});
