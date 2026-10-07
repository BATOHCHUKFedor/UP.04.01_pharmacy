'use strict';

const { HttpError } = require('./http-error');

function createAccountRoutes({ auth, getDb, transaction, readBody, now = Date.now }) {
  const invalid = errors => { throw new HttpError(422, 'Проверьте поля формы.', errors); };
  const present = item => ({ ...item });
  async function publicRoutes(req, parts, send) {
    if (parts[1] !== 'auth') return false;
    const action = parts[2];
    if (parts.length !== 3) throw new HttpError(404, 'Адрес авторизации не найден.');
    if (req.method === 'POST' && action === 'login') send(200, auth.login(await readBody(req)));
    else if (req.method === 'POST' && action === 'register') {
      const body = await readBody(req);
      auth.addUser(body); // Публичная регистрация всегда создаёт обычного пользователя.
      send(201, auth.login(body));
    } else if (req.method === 'POST' && action === 'refresh') send(200, auth.refresh(await readBody(req)));
    else if (req.method === 'POST' && action === 'logout') {
      auth.logout(await readBody(req));
      send(204);
    } else if (req.method === 'GET' && action === 'me') send(200, auth.me(auth.authenticate(req)));
    else if (req.method === 'POST' && action === 'activity') send(200, auth.activity(auth.authenticate(req)));
    else throw new HttpError(405, 'Операция авторизации не поддерживается.');
    return true;
  }
  async function protectedRoutes(req, parts, actor, send) {
    const rows = getDb();
    const method = req.method;
    if (parts[1] === 'admin') {
      if (parts[2] === 'statistics' && parts.length === 3 && method === 'GET') {
        auth.requirePermission(actor.user, 'statistics');
        const drugs = rows.drugs.filter(d => !d.deletedAt);
        send(200, { drugs: drugs.length, stock: drugs.reduce((sum, d) => sum + d.stock, 0),
          users: rows.auth.users.length, customers: rows.auth.users.filter(u => u.role === 'customer').length,
          reserved: rows.reservations.filter(r => r.status === 'reserved').length,
          completed: rows.reservations.filter(r => r.status === 'completed').length });
        return true;
      }
      auth.requirePermission(actor.user, 'users');
      if (parts[2] !== 'users') throw new HttpError(404, 'Административный раздел не найден.');
      if (parts.length === 3 && method === 'GET') send(200, rows.auth.users.map(auth.publicUser));
      else if (parts.length === 3 && method === 'POST') {
        const body = await readBody(req);
        send(201, auth.publicUser(auth.addUser(body, body.role)));
      } else if (parts.length === 4 && method === 'PUT') {
        send(200, auth.updateUser(actor, Number(parts[3]), await readBody(req)));
      } else throw new HttpError(405, 'Операция с пользователями не поддерживается.');
      return true;
    }
    if (parts[1] === 'customers') {
      auth.requirePermission(actor.user, 'customers');
      if (parts.length !== 2) throw new HttpError(404, 'Раздел пользователей аптеки не найден.');
      if (method === 'GET') send(200, rows.auth.users.filter(u => u.role === 'customer').map(auth.publicUser));
      else if (method === 'POST') send(201, auth.publicUser(auth.addUser(await readBody(req))));
      else throw new HttpError(405, 'Операция с пользователями не поддерживается.');
      return true;
    }
    if (parts[1] !== 'reservations') return false;
    if (parts[2] === 'mine' && parts.length === 3 && method === 'GET') {
      auth.requirePermission(actor.user, 'reservations.mine');
      send(200, rows.reservations.filter(r => r.userId === actor.user.id).map(present));
      return true;
    }
    if (parts.length === 2 && method === 'GET') {
      auth.requirePermission(actor.user, 'reservations.manage');
      send(200, rows.reservations.map(present));
      return true;
    }
    if (parts.length === 2 && method === 'POST') {
      auth.requirePermission(actor.user, 'reservations.manage');
      const body = await readBody(req);
      const item = transaction(next => {
        const drug = next.drugs.find(d => d.id === body.drugId && !d.deletedAt);
        const user = next.auth.users.find(u => u.id === body.userId && u.role === 'customer' && u.active);
        const errors = {};
        if (!drug) errors.drugId = 'Выберите действующий препарат';
        if (!user) errors.userId = 'Выберите действующего пользователя';
        if (!Number.isInteger(body.quantity) || body.quantity < 1 || body.quantity > 1000000) {
          errors.quantity = 'Количество: целое число от 1 до 1000000';
        }
        if (Object.keys(errors).length) invalid(errors);
        if (drug.stock < body.quantity) throw new HttpError(409, `Недостаточно упаковок. Доступно: ${drug.stock}.`);
        drug.stock -= body.quantity;
        const reservation = { id: next.nextReservationId++, userId: user.id, customerName: user.name,
          drugId: drug.id, drugName: drug.name, quantity: body.quantity, status: 'reserved',
          expiresAt: new Date(now() + 3 * 86400000).toISOString(), extended: false };
        next.reservations.push(reservation);
        return reservation;
      });
      send(201, present(item));
      return true;
    }
    const action = parts[3];
    if (method !== 'POST' || parts.length !== 4 || !['extend', 'complete', 'cancel'].includes(action)) {
      throw new HttpError(405, 'Операция с бронированием не поддерживается.');
    }
    auth.requirePermission(actor.user, action === 'extend' ? 'reservations.extend' : 'reservations.manage');
    const changed = transaction(next => {
      const item = next.reservations.find(r => r.id === Number(parts[2]));
      if (!item) throw new HttpError(404, 'Бронирование не найдено.');
      if (action === 'extend' && item.userId !== actor.user.id) throw new HttpError(403, 'Можно продлевать только собственные бронирования.');
      if (item.status !== 'reserved') throw new HttpError(409, 'Бронирование уже завершено.');
      if (action === 'extend') {
        if (item.extended || Date.parse(item.expiresAt) <= now()) throw new HttpError(409, 'Это бронирование нельзя продлить.');
        item.expiresAt = new Date(Date.parse(item.expiresAt) + 3 * 86400000).toISOString();
        item.extended = true;
      } else {
        item.status = action === 'complete' ? 'completed' : 'cancelled';
        if (action === 'cancel') {
          const drug = next.drugs.find(d => d.id === item.drugId);
          if (!drug) throw new HttpError(409, 'Связанный препарат не найден.');
          drug.stock += item.quantity;
        }
      }
      return item;
    });
    send(200, present(changed));
    return true;
  }
  return { publicRoutes, protectedRoutes };
}

module.exports = { createAccountRoutes };
