'use strict';

const crypto = require('node:crypto');
const { HttpError } = require('./http-error');

const roles = ['customer', 'pharmacist', 'admin'];
const permissions = {
  customer: new Set(['catalog.read', 'reservations.mine', 'reservations.extend']),
  pharmacist: new Set(['catalog.read', 'catalog.write', 'catalog.delete', 'dispense', 'customers', 'reservations.manage']),
  admin: new Set(['catalog.read', 'catalog.write', 'catalog.delete', 'catalog.hardDelete', 'catalog.restore', 'users', 'statistics']),
};
const hashToken = token => crypto.createHash('sha256').update(token).digest('hex');
const equal = (a, b) => a.length === b.length && crypto.timingSafeEqual(a, b);
const scryptOptions = { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 };
function passwordHash(password, salt = crypto.randomBytes(16).toString('hex')) {
  return { salt, hash: crypto.scryptSync(password, salt, 64, scryptOptions).toString('hex') };
}
function verifyPassword(password, stored) {
  const candidate = passwordHash(password, stored.salt);
  return equal(Buffer.from(candidate.hash, 'hex'), Buffer.from(stored.hash, 'hex'));
}
const publicUser = user => ({ id: user.id, username: user.username, name: user.name, role: user.role, active: user.active });
let demoUsers;
function initialUsers() {
  // Только учебные аккаунты. Пароли в хранилище представлены scrypt-хешами с солью.
  demoUsers ??= [
    { id: 1, username: 'customer', name: 'Анна Пользователь', role: 'customer', password: passwordHash('Customer123!'), active: true },
    { id: 2, username: 'pharmacist', name: 'Ольга Фармацевт', role: 'pharmacist', password: passwordHash('Pharmacist123!'), active: true },
    { id: 3, username: 'admin', name: 'Иван Администратор', role: 'admin', password: passwordHash('Admin123!'), active: true },
  ];
  return structuredClone(demoUsers);
}

function createAuth({ getDb, transaction, ttl = 900, sessionTtl = 3600, idleTtl = 180, now = Date.now }) {
  if (![ttl, sessionTtl, idleTtl].every(value => Number.isFinite(value) && value > 0)) {
    throw new Error('Сроки действия токена и сессии должны быть положительными.');
  }
  const db = getDb();
  db.auth ??= { version: 1, secret: crypto.randomBytes(32).toString('base64'), users: initialUsers(), sessions: [], nextUserId: 4 };
  if (db.auth.version !== 1) throw new Error('Неподдерживаемая версия данных авторизации.');
  db.reservations ??= [];
  db.nextReservationId ??= Math.max(0, ...db.reservations.map(item => item.id)) + 1;
  const secret = Buffer.from(db.auth.secret, 'base64');
  const requirePermission = (user, operation) => {
    if (!permissions[user.role]?.has(operation)) throw new HttpError(403, 'Недостаточно прав для этого действия.');
  };
  function liveSession(rows, session) {
    if (!session || session.revoked || now() >= session.expiresAt || now() >= session.refreshExpiresAt ||
        now() - session.lastActivity >= idleTtl * 1000) {
      throw new HttpError(401, 'Сессия завершена. Войдите снова.');
    }
    const user = rows.auth.users.find(candidate => candidate.id === session.userId);
    if (!user?.active) throw new HttpError(401, 'Учётная запись недоступна.');
    return user;
  }
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  function accessToken(user, session) {
    const header = encode({ alg: 'HS256', typ: 'JWT' });
    const payload = encode({ sub: String(user.id), sid: session.id, role: user.role,
      iss: 'pharmacy-api', aud: 'pharmacy-web', iat: Math.floor(now() / 1000),
      exp: Math.min(Math.ceil(session.expiresAt / 1000), Math.floor(now() / 1000) + ttl) });
    const signed = `${header}.${payload}`;
    return `${signed}.${crypto.createHmac('sha256', secret).update(signed).digest('base64url')}`;
  }
  function sessionInfo(session) {
    return { id: session.id, startedAt: session.startedAt, expiresAt: session.expiresAt,
      lastActivity: session.lastActivity, idleSeconds: idleTtl, warningSeconds: Math.min(30, idleTtl / 2) };
  }
  function issue(rows, user, session) {
    const refreshToken = crypto.randomBytes(32).toString('base64url');
    // Предыдущий refresh больше не обновляет токены, но ещё может отозвать
    // сессию: пользователь мог нажать «Выйти» во время обновления.
    session.previousRefreshHash = session.refreshHash;
    session.refreshHash = hashToken(refreshToken);
    return { user: publicUser(user), accessToken: accessToken(user, session), refreshToken,
      session: sessionInfo(session) };
  }
  function authenticate(req) {
    try {
      const token = req.headers.authorization?.match(/^Bearer ([\w.-]+)$/)?.[1];
      if (!token || token.length > 8192) throw new Error();
      const [header, payload, signature, extra] = token.split('.');
      if (!header || !payload || !signature || extra) throw new Error();
      const expected = crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest();
      if (!equal(expected, Buffer.from(signature, 'base64url'))) throw new Error();
      const algorithm = JSON.parse(Buffer.from(header, 'base64url').toString());
      const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
      if (algorithm.alg !== 'HS256' || claims.iss !== 'pharmacy-api' || claims.aud !== 'pharmacy-web' ||
          !Number.isFinite(claims.exp) || now() / 1000 >= claims.exp) throw new Error();
      const rows = getDb();
      const session = rows.auth.sessions.find(candidate => candidate.id === claims.sid);
      const user = liveSession(rows, session);
      if (String(user.id) !== claims.sub) throw new Error();
      // Права берутся из серверной записи пользователя, не из JSON профиля клиента.
      return { user, session };
    } catch (error) {
      if (error instanceof HttpError) throw error;
      throw new HttpError(401, 'Токен недействителен или истёк. Войдите снова.');
    }
  }
  function credentials(body) {
    const errors = {};
    const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
    const name = typeof body.name === 'string' ? body.name.trim() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    if (!/^[a-z0-9_.-]{3,40}$/.test(username)) errors.username = 'Логин: 3–40 латинских букв, цифр, точек, дефисов или подчёркиваний';
    if (name.length < 2 || name.length > 80) errors.name = 'Имя: от 2 до 80 символов';
    if (password.length < 8 || password.length > 128 || !/\d/.test(password) || !/[^\p{L}\p{N}\s]/u.test(password)) {
      errors.password = 'Пароль: 8–128 символов, хотя бы одна цифра и специальный символ';
    }
    if (getDb().auth.users.some(user => user.username === username)) errors.username = 'Этот логин уже занят';
    if (Object.keys(errors).length) throw new HttpError(422, 'Проверьте поля формы.', errors);
    return { username, name, password: passwordHash(password), active: true };
  }
  function addUser(body, role = 'customer') {
    if (!roles.includes(role)) throw new HttpError(422, 'Проверьте роль.', { role: 'Выберите допустимую роль' });
    const input = credentials(body);
    return transaction(rows => {
      const user = { ...input, id: rows.auth.nextUserId++, role };
      rows.auth.users.push(user);
      return user;
    });
  }
  function login(body) {
    const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    if (!username || !password) throw new HttpError(422, 'Заполните логин и пароль.', {
      ...(!username ? { username: 'Заполните поле' } : {}), ...(!password ? { password: 'Заполните поле' } : {}),
    });
    const user = getDb().auth.users.find(candidate => candidate.username === username);
    const valid = verifyPassword(password.slice(0, 129), user?.password ?? initialUsers()[0].password);
    if (!user?.active || !valid || password.length > 128) throw new HttpError(401, 'Неверный логин или пароль.');
    return transaction(rows => {
      const time = now();
      const session = { id: crypto.randomUUID(), userId: user.id, startedAt: time,
        expiresAt: time + sessionTtl * 1000, refreshExpiresAt: time + 7 * 86400000,
        lastActivity: time, revoked: false };
      rows.auth.sessions = rows.auth.sessions.filter(s => !s.revoked && s.refreshExpiresAt > time);
      rows.auth.sessions.push(session);
      return issue(rows, user, session);
    });
  }
  function refresh(body) {
    if (typeof body.refreshToken !== 'string') throw new HttpError(401, 'Требуется повторный вход.');
    return transaction(rows => {
      const session = rows.auth.sessions.find(s => s.refreshHash === hashToken(body.refreshToken));
      const user = liveSession(rows, session);
      return issue(rows, user, session);
    });
  }
  function logout(body) {
    if (typeof body.refreshToken !== 'string') return;
    transaction(rows => {
      const hash = hashToken(body.refreshToken);
      const session = rows.auth.sessions.find(s => s.refreshHash === hash || s.previousRefreshHash === hash);
      if (session) session.revoked = true;
    });
  }
  function activity(actor) {
    return transaction(rows => {
      const session = rows.auth.sessions.find(s => s.id === actor.session.id);
      liveSession(rows, session);
      session.lastActivity = now();
      return sessionInfo(session);
    });
  }
  function updateUser(actor, id, body) {
    requirePermission(actor.user, 'users');
    return transaction(rows => {
      const user = rows.auth.users.find(candidate => candidate.id === id);
      if (!user) throw new HttpError(404, 'Пользователь не найден.');
      const role = body.role ?? user.role;
      const active = body.active ?? user.active;
      if (!roles.includes(role) || typeof active !== 'boolean') throw new HttpError(422, 'Некорректные права пользователя.');
      if (user.role === 'admin' && user.active && (role !== 'admin' || !active) &&
          rows.auth.users.filter(u => u.role === 'admin' && u.active).length === 1) {
        throw new HttpError(409, 'Нельзя отключить или понизить последнего администратора.');
      }
      user.role = role;
      user.active = active;
      rows.auth.sessions.filter(s => s.userId === id).forEach(s => { s.revoked = true; });
      return publicUser(user);
    });
  }
  return { authenticate, requirePermission, login, refresh, logout, activity, addUser, updateUser, publicUser,
    me: actor => ({ user: publicUser(actor.user), session: sessionInfo(actor.session) }) };
}

module.exports = { createAuth, permissions, roles };
