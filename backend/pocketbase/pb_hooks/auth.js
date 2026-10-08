'use strict';
const c = require(__hooks + '/core.js');
const roles = ['customer', 'pharmacist', 'admin'];
const permissions = {
  customer: ['catalog.read', 'reservations.mine', 'reservations.extend'],
  pharmacist: ['catalog.read', 'catalog.write', 'catalog.delete', 'dispense', 'customers', 'reservations.manage'],
  admin: ['catalog.read', 'catalog.write', 'catalog.delete', 'catalog.hardDelete', 'catalog.restore', 'users', 'statistics'],
};
function duration(name, fallback) {
  const value = Number($os.getenv(name) || fallback);
  if (!Number.isInteger(value) || value < 1 || value > 604800) throw new Error('Invalid duration: ' + name);
  return value;
}
function permission(user, operation) {
  if (!(permissions[user.getString('role')] || []).includes(operation))
    c.fail(403, 'Недостаточно прав для этого действия.');
}
function userDto(user) {
  return { id: user.getInt('code'), username: user.getString('username'), name: user.getString('name'),
    role: user.getString('role'), active: user.getBool('active') };
}
function sessionDto(session) {
  const idle = duration('PHARMACY_IDLE_TTL', 180);
  return { id: session.id, startedAt: session.getInt('startedAt'), expiresAt: session.getInt('expiresAt'),
    lastActivity: session.getInt('lastActivity'), idleSeconds: idle, warningSeconds: Math.min(30, idle / 2) };
}
function live(app, session) {
  if (!session || session.getBool('revoked') || Date.now() >= session.getInt('expiresAt') ||
      Date.now() - session.getInt('lastActivity') >= duration('PHARMACY_IDLE_TTL', 180) * 1000)
    c.fail(401, 'Сессия завершена. Войдите снова.');
  const user = c.byId(app, 'pharmacy_users', session.getString('user'));
  if (!user || !user.getBool('active')) c.fail(401, 'Учётная запись недоступна.');
  return user;
}
function secret(app) { return c.first(app, 'pharmacy_config', "name = 'jwt-secret'").getString('value'); }
function issue(app, user, session) {
  const refreshToken = $security.randomString(64);
  session.set('previousRefreshHash', session.getString('refreshHash'));
  session.set('refreshHash', $security.sha256(refreshToken));
  app.save(session);
  const ttl = Math.min(duration('PHARMACY_ACCESS_TTL', 900), Math.floor((session.getInt('expiresAt') - Date.now()) / 1000));
  if (ttl < 1) c.fail(401, 'Сессия завершена. Войдите снова.');
  const accessToken = $security.createJWT({
    sub: user.id, sid: session.id, role: user.getString('role'), iss: 'pharmacy-pocketbase', aud: 'pharmacy-web',
  }, secret(app), ttl);
  return { user: userDto(user), accessToken, refreshToken, session: sessionDto(session) };
}
function authenticate(app, e) {
  try {
    const match = e.request.header.get('Authorization').match(/^Bearer ([\w.-]+)$/);
    if (!match || match[1].length > 8192) throw new Error('Invalid token');
    const claims = $security.parseJWT(match[1], secret(app));
    if (claims.iss !== 'pharmacy-pocketbase' || claims.aud !== 'pharmacy-web' ||
        typeof claims.exp !== 'number' || Date.now() / 1000 >= claims.exp) throw new Error('Invalid claims');
    const session = c.byId(app, 'pharmacy_sessions', claims.sid);
    const user = live(app, session);
    if (user.id !== claims.sub) throw new Error('Invalid subject');
    // JWT role and localStorage profile are NOT authorization sources.
    return { user, session };
  } catch (error) {
    if (error.status) throw error;
    c.fail(401, 'Токен недействителен или истёк. Войдите снова.');
  }
}
function hasSpecial(app, password) {
  // Goja does not implement Unicode property escapes like the browser does.
  // Use PocketBase's native Go regexp validator, not a JavaScript regexp.
  const candidate = new Record(app.findCollectionByNameOrId('pharmacy_config'));
  candidate.set('value', password);
  try {
    new TextField({ name: 'value', pattern: '[^\\p{L}\\p{N}\\s]' }).validateValue(null, app, candidate);
    return true;
  } catch (_) { return false; }
}
function passwordInput(password) {
  // bcrypt accepts at most 72 bytes. Prehash avoids truncation/rejection for
  // our existing 8–128 UTF-16-character contract, including non-ASCII passwords.
  // Native password auth is disabled; only these handlers verify app passwords.
  return $security.sha256(password);
}
function addUser(app, body, role = 'customer') {
  const errors = {};
  const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  if (!/^[a-z0-9_.-]{3,40}$/.test(username)) errors.username = 'Логин: 3–40 латинских букв, цифр, точек, дефисов или подчёркиваний';
  if (name.length < 2 || name.length > 80) errors.name = 'Имя: от 2 до 80 символов';
  if (password.length < 8 || password.length > 128 || !/\d/.test(password) || !hasSpecial(app, password))
    errors.password = 'Пароль: 8–128 символов, хотя бы одна цифра и специальный символ';
  if (!roles.includes(role)) errors.role = 'Выберите допустимую роль';
  if (c.first(app, 'pharmacy_users', 'usernameKey = {:key}', { key: username })) errors.username = 'Этот логин уже занят';
  if (Object.keys(errors).length) c.invalid(errors);
  const user = new Record(app.findCollectionByNameOrId('pharmacy_users'));
  user.set('code', c.nextCode(app, 'pharmacy_users'));
  user.set('username', username); user.set('usernameKey', username); user.set('name', name);
  user.set('role', role); user.set('active', true); user.setPassword(passwordInput(password));
  app.save(user);
  return user;
}
function login(app, body) {
  const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  if (!username || !password) c.invalid({ ...(!username ? { username: 'Заполните поле' } : {}),
    ...(!password ? { password: 'Заполните поле' } : {}) });
  const user = c.first(app, 'pharmacy_users', 'usernameKey = {:username}', { username });
  if (!user || !user.getBool('active') || password.length > 128 || !user.validatePassword(passwordInput(password)))
    c.fail(401, 'Неверный логин или пароль.');
  const session = new Record(app.findCollectionByNameOrId('pharmacy_sessions'));
  session.set('user', user.id); session.set('startedAt', Date.now()); session.set('lastActivity', Date.now());
  session.set('expiresAt', Date.now() + duration('PHARMACY_SESSION_TTL', 3600) * 1000);
  return issue(app, user, session);
}
function refresh(app, body) {
  if (typeof body.refreshToken !== 'string' || body.refreshToken.length > 1024) c.fail(401, 'Требуется повторный вход.');
  const session = c.first(app, 'pharmacy_sessions', 'refreshHash = {:hash}', { hash: $security.sha256(body.refreshToken) });
  return issue(app, live(app, session), session);
}
function logout(app, body) {
  if (typeof body.refreshToken !== 'string' || body.refreshToken.length > 1024) return;
  const hash = $security.sha256(body.refreshToken);
  const session = c.first(app, 'pharmacy_sessions', 'refreshHash = {:hash} || previousRefreshHash = {:hash}', { hash });
  if (session) { session.set('revoked', true); app.save(session); }
}
function updateUser(app, code, body) {
  const user = c.byCode(app, 'pharmacy_users', code);
  const role = body.role === undefined ? user.getString('role') : body.role;
  const active = body.active === undefined ? user.getBool('active') : body.active;
  const errors = {};
  if (!roles.includes(role)) errors.role = 'Выберите допустимую роль';
  if (typeof active !== 'boolean') errors.active = 'Выберите состояние учётной записи';
  if (Object.keys(errors).length) c.invalid(errors);
  if (user.getString('role') === 'admin' && user.getBool('active') && (role !== 'admin' || !active) &&
      c.count(app, 'pharmacy_users', "role = 'admin' AND active = 1") === 1)
    c.fail(409, 'Нельзя отключить или понизить последнего администратора.');
  user.set('role', role); user.set('active', active); app.save(user);
  c.rows(app, 'pharmacy_sessions', 'user = {:id}', { id: user.id }).forEach(session => {
    session.set('revoked', true); app.save(session);
  });
  return userDto(user);
}
module.exports = { permission, userDto, sessionDto, authenticate, addUser, login, refresh, logout, updateUser, live };
