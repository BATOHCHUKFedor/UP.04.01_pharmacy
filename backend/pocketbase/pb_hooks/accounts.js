'use strict';
const c = require(__hooks + '/core.js');
const auth = require(__hooks + '/auth.js');
function reservationDto(app, row) {
  return { id: row.getInt('code'), userId: c.byId(app, 'pharmacy_users', row.getString('user')).getInt('code'),
    drugId: c.byId(app, 'drugs', row.getString('drug')).getInt('code'),
    customerName: row.getString('customerName'), drugName: row.getString('drugName'),
    quantity: row.getInt('quantity'), status: row.getString('status'),
    expiresAt: c.iso(row.getString('expiresAt')), extended: row.getBool('extended') };
}
function dispatch(app, parts, method, body, actor) {
  const result = (value, status = 200) => ({ status, body: value });
  if (parts[0] === 'admin') {
    if (parts[1] === 'statistics' && parts.length === 2 && method === 'GET') {
      auth.permission(actor.user, 'statistics');
      const totals = new DynamicModel({ drugs: 0, stock: 0 });
      app.db().newQuery("SELECT COUNT(*) AS drugs, COALESCE(SUM(stock), 0) AS stock FROM drugs WHERE deletedAt = ''").one(totals);
      return result({ drugs: totals.drugs, stock: totals.stock, users: c.count(app, 'pharmacy_users'),
        customers: c.count(app, 'pharmacy_users', "role = 'customer'"),
        reserved: c.count(app, 'pharmacy_reservations', "status = 'reserved'"),
        completed: c.count(app, 'pharmacy_reservations', "status = 'completed'") });
    }
    auth.permission(actor.user, 'users');
    if (parts[1] !== 'users') c.fail(404, 'Административный раздел не найден.');
    if (parts.length === 2 && method === 'GET') return result(c.rows(app, 'pharmacy_users').map(auth.userDto));
    if (parts.length === 2 && method === 'POST') return result(auth.userDto(auth.addUser(app, body, body.role)), 201);
    if (parts.length === 3 && method === 'PUT') return result(auth.updateUser(app, Number(parts[2]), body));
    c.fail(405, 'Операция с пользователями не поддерживается.');
  }
  if (parts[0] === 'customers') {
    auth.permission(actor.user, 'customers');
    if (parts.length !== 1) c.fail(404, 'Раздел пользователей аптеки не найден.');
    if (method === 'GET') return result(c.rows(app, 'pharmacy_users', "role = 'customer'").map(auth.userDto));
    if (method === 'POST') return result(auth.userDto(auth.addUser(app, body)), 201);
    c.fail(405, 'Операция с пользователями не поддерживается.');
  }
  if (parts[0] !== 'reservations') return null;
  if (parts[1] === 'mine' && parts.length === 2 && method === 'GET') {
    auth.permission(actor.user, 'reservations.mine');
    return result(c.rows(app, 'pharmacy_reservations', 'user = {:id}', { id: actor.user.id }).map(row => reservationDto(app, row)));
  }
  if (parts.length === 1 && method === 'GET') {
    auth.permission(actor.user, 'reservations.manage');
    return result(c.rows(app, 'pharmacy_reservations').map(row => reservationDto(app, row)));
  }
  if (parts.length === 1 && method === 'POST') {
    auth.permission(actor.user, 'reservations.manage');
    const errors = {};
    const drug = Number.isInteger(body.drugId) ? c.byCode(app, 'drugs', body.drugId, false) : null;
    const user = Number.isInteger(body.userId) ? c.byCode(app, 'pharmacy_users', body.userId, false) : null;
    if (!c.active(drug)) errors.drugId = 'Выберите действующий препарат';
    if (!user || !user.getBool('active') || user.getString('role') !== 'customer') errors.userId = 'Выберите действующего пользователя';
    if (!Number.isInteger(body.quantity) || body.quantity < 1 || body.quantity > 1000000)
      errors.quantity = 'Количество: целое число от 1 до 1000000';
    if (Object.keys(errors).length) c.invalid(errors);
    if (drug.getInt('stock') < body.quantity) c.fail(409, 'Недостаточно упаковок. Доступно: ' + drug.getInt('stock') + '.');
    drug.set('stock', drug.getInt('stock') - body.quantity); app.save(drug);
    const row = new Record(app.findCollectionByNameOrId('pharmacy_reservations'));
    row.set('code', c.nextCode(app, 'pharmacy_reservations')); row.set('drug', drug.id); row.set('user', user.id);
    row.set('customerName', user.getString('name')); row.set('drugName', drug.getString('name'));
    row.set('quantity', body.quantity); row.set('status', 'reserved'); row.set('extended', false);
    row.set('expiresAt', new Date(Date.now() + 3 * 86400000).toISOString()); app.save(row);
    return result(reservationDto(app, row), 201);
  }
  const action = parts[2];
  if (method !== 'POST' || parts.length !== 3 || !['extend', 'complete', 'cancel'].includes(action))
    c.fail(405, 'Операция с бронированием не поддерживается.');
  auth.permission(actor.user, action === 'extend' ? 'reservations.extend' : 'reservations.manage');
  const row = c.byCode(app, 'pharmacy_reservations', Number(parts[1]));
  if (action === 'extend' && row.getString('user') !== actor.user.id) c.fail(403, 'Можно продлевать только собственные бронирования.');
  if (row.getString('status') !== 'reserved') c.fail(409, 'Это бронирование уже закрыто.');
  if (action === 'extend') {
    if (row.getBool('extended') || new Date(row.getString('expiresAt')).getTime() <= Date.now())
      c.fail(409, 'Продление недоступно: срок истёк или бронирование уже продлевалось.');
    row.set('expiresAt', new Date(new Date(row.getString('expiresAt')).getTime() + 3 * 86400000).toISOString());
    row.set('extended', true);
  } else {
    row.set('status', action === 'complete' ? 'completed' : 'cancelled');
    if (action === 'cancel') {
      const drug = c.byId(app, 'drugs', row.getString('drug'));
      if (drug.getInt('stock') + row.getInt('quantity') > 1000000) c.fail(409, 'Возврат превысит допустимый запас препарата.');
      drug.set('stock', drug.getInt('stock') + row.getInt('quantity')); app.save(drug);
    }
  }
  app.save(row);
  return result(reservationDto(app, row));
}
module.exports = { dispatch };
