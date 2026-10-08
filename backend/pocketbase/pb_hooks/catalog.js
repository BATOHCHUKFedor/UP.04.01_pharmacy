'use strict';
const c = require(__hooks + '/core.js');

function save(app, kind, body, code = 0) {
  const original = code ? c.byCode(app, kind, code) : null;
  if (original && !c.active(original)) c.fail(409, 'Сначала восстановите удалённую запись.');
  const errors = {}, values = {};
  const text = (key, max) => {
    const value = typeof body[key] === 'string' ? body[key].trim() : '';
    values[key] = value;
    if (!value) errors[key] = 'Заполните поле';
    else if (value.length > max) errors[key] = 'Не более ' + max + ' символов';
    return value;
  };
  const number = (key, min, max, integer = true) => {
    const value = body[key];
    values[key] = value;
    if (typeof value !== 'number' || !Number.isFinite(value) || (integer && !Number.isInteger(value)))
      errors[key] = integer ? 'Введите целое число' : 'Введите число';
    else if (value < min || value > max) errors[key] = 'Число от ' + min + ' до ' + max;
  };
  const email = key => {
    text(key, 254);
    if (!errors[key] && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values[key]))
      errors[key] = 'Введите корректный адрес почты';
  };
  const reference = (key, field, target) => {
    const row = Number.isInteger(body[key]) ? c.byCode(app, target, body[key], false) : null;
    if (!c.active(row)) errors[key] = 'Выберите действующую запись';
    values[field] = row ? row.id : '';
    return row;
  };
  const references = (key, field, target) => {
    const codes = Array.isArray(body[key]) ? Array.from(new Set(body[key])) : [];
    const records = codes.map(id => Number.isInteger(id) ? c.byCode(app, target, id, false) : null);
    if (!records.length || records.length > 100 || records.some(row => !c.active(row)))
      errors[key] = 'Выберите от 1 до 100 действующих записей';
    values[field] = records.filter(Boolean).map(row => row.id);
  };
  const unique = (field, value, key, message) => {
    const found = c.first(app, kind, field + ' = {:value} && code != {:code}', { value, code });
    if (found) errors[key] = message;
  };
  if (kind !== 'licenses') text('name', kind === 'categories' ? 100 : 120);
  if (kind === 'drugs') {
    text('registrationNumber', 40);
    values.registrationKey = values.registrationNumber.toLowerCase();
    const manufacturer = reference('manufacturerId', 'manufacturer', 'manufacturers');
    const supplier = reference('supplierId', 'supplier', 'suppliers');
    references('categoryIds', 'categories', 'categories');
    number('productionYear', 1900, 2100); number('price', 0.01, 10000000, false); number('stock', 0, 1000000);
    unique('registrationKey', values.registrationKey, 'registrationNumber', 'Такой регистрационный номер уже существует');
    if (!errors.manufacturerId && !errors.supplierId &&
        !Array.from(supplier.getStringSlice('manufacturers')).includes(manufacturer.id))
      errors.supplierId = 'Поставщик не работает с выбранным производителем';
  } else if (kind === 'suppliers') {
    text('contactPerson', 120); text('country', 80); text('phone', 30); email('email');
    // Spaces, parentheses and hyphens are allowed; the underlying number has 7–15 digits.
    if (!errors.phone && (!/^\+?[\d ()-]+$/.test(values.phone) ||
        !/^\d{7,15}$/.test(values.phone.replace(/\D/g, '')))) errors.phone = 'Телефон: от 7 до 15 цифр';
    values.emailKey = values.email.toLowerCase();
    number('partnershipYear', 1900, 2100); references('manufacturerIds', 'manufacturers', 'manufacturers');
    unique('emailKey', values.emailKey, 'email', 'Такой адрес почты уже существует');
    if (original) {
      const linked = c.rows(app, 'drugs', 'supplier = {:id}', { id: original.id });
      if (linked.some(row => !values.manufacturers.includes(row.getString('manufacturer'))))
        errors.manufacturerIds = 'Нельзя убрать производителя: с ним связаны препараты этого поставщика';
    }
  } else if (kind === 'manufacturers') {
    text('country', 80); email('contactEmail');
  } else if (kind === 'categories') {
    text('description', 250);
  } else {
    reference('supplierId', 'supplier', 'suppliers'); text('number', 40);
    number('issuedYear', 1900, 2100); number('expiresYear', 1900, 2200);
    if (!errors.expiresYear && !errors.issuedYear && values.expiresYear < values.issuedYear)
      errors.expiresYear = 'Год окончания должен быть не раньше года выдачи';
    unique('supplier', values.supplier, 'supplierId', 'У этого поставщика уже есть лицензия');
  }
  if (Object.keys(errors).length) c.invalid(errors);
  const row = original || new Record(app.findCollectionByNameOrId(kind));
  if (!original) row.set('code', c.nextCode(app, kind));
  Object.keys(values).forEach(key => row.set(key, values[key]));
  row.set('searchText', ['name', 'registrationNumber', 'contactPerson', 'country', 'email', 'contactEmail', 'description', 'number']
    .map(key => values[key] || '').join(' ').toLowerCase());
  app.save(row);
  if (kind === 'suppliers' && body.license != null) {
    const license = c.first(app, 'licenses', 'supplier = {:id}', { id: row.id });
    // Reuse the existing 1:1 license even if it was individually soft-deleted.
    if (license && !c.active(license)) { license.set('deletedAt', ''); app.save(license); }
    try {
      save(app, 'licenses', { ...body.license, supplierId: row.getInt('code') }, license ? license.getInt('code') : 0);
    } catch (error) {
      if (error.errors && error.errors.number) {
        error.errors.licenseNumber = error.errors.number; delete error.errors.number;
      }
      throw error;
    }
  }
  return row;
}

function checkDeletion(app, kind, row) {
  let count = 0;
  if (kind === 'drugs') {
    count = c.count(app, 'pharmacy_reservations', "drug = {:id} AND status = 'reserved'", { id: row.id });
    if (count) c.fail(409, 'Удаление невозможно: действующих бронирований — ' + count);
    // Historical reservations must keep their real FK even after fulfilment.
    return;
  }
  if (kind === 'manufacturers') count = c.count(app, 'drugs', 'manufacturer = {:id}', { id: row.id });
  if (kind === 'suppliers') count = c.count(app, 'drugs', 'supplier = {:id}', { id: row.id });
  if (kind === 'categories') count = c.count(app, 'drugs',
    'EXISTS (SELECT 1 FROM json_each(categories) WHERE value = {:id})', { id: row.id });
  if (count) c.fail(409, 'Удаление невозможно: связанных препаратов — ' + count);
  if (kind === 'manufacturers') {
    count = c.count(app, 'suppliers', 'EXISTS (SELECT 1 FROM json_each(manufacturers) WHERE value = {:id})', { id: row.id });
    if (count) c.fail(409, 'Удаление невозможно: связанных поставщиков — ' + count);
  }
}
function remove(app, kind, row, hard = false) {
  checkDeletion(app, kind, row);
  if (hard && kind === 'drugs') {
    const history = c.count(app, 'pharmacy_reservations', 'drug = {:id}', { id: row.id });
    if (history) c.fail(409, 'Физическое удаление невозможно: записей в истории бронирований — ' + history);
  }
  const licenses = kind === 'suppliers' ? c.rows(app, 'licenses', 'supplier = {:id}', { id: row.id }) : [];
  if (hard) {
    licenses.forEach(license => app.delete(license)); app.delete(row); return null;
  }
  const deletedAt = row.getString('deletedAt') || new Date().toISOString();
  row.set('deletedAt', deletedAt); app.save(row);
  licenses.forEach(license => { license.set('deletedAt', deletedAt); app.save(license); });
  return row;
}
function restore(app, kind, row) {
  row.set('deletedAt', ''); app.save(row);
  // Revalidate all references inside the same transaction. Failure rolls back the restore.
  const input = c.dto(app, kind, row);
  if (kind === 'drugs') {
    input.manufacturerId = input.manufacturer ? input.manufacturer.id : 0;
    input.supplierId = input.supplier ? input.supplier.id : 0;
    input.categoryIds = input.categories.map(item => item.id);
  }
  if (kind === 'suppliers') input.manufacturerIds = input.manufacturers.map(item => item.id);
  try {
    save(app, kind, input, row.getInt('code'));
    if (kind === 'suppliers') c.rows(app, 'licenses', 'supplier = {:id}', { id: row.id }).forEach(license => {
      restore(app, 'licenses', license);
    });
  } catch (error) {
    if (error.status === 422) c.fail(409, 'Восстановление невозможно: проверьте связанные записи.', error.errors);
    throw error;
  }
  return row;
}

function list(app, kind, q) {
  const conditions = [], params = {};
  if (q.includeDeleted !== 'true') conditions.push("deletedAt = ''");
  const search = typeof q.search === 'string' ? q.search.trim().toLowerCase() : '';
  if (search.length > 200) c.invalid({ search: 'Не более 200 символов' });
  if (search) {
    // instr treats '%' and '_' literally; searchText supplies Unicode lowercase at write time.
    conditions.push(kind === 'licenses'
      ? '(instr(searchText, {:search}) > 0 OR supplier IN (SELECT id FROM suppliers WHERE instr(searchText, {:search}) > 0))'
      : 'instr(searchText, {:search}) > 0');
    params.search = search;
  }
  const refFilter = (key, field, target, multiple = false) => {
    if (q[key] === undefined) return;
    const code = Number(q[key]);
    if (!Number.isInteger(code) || code <= 0) c.invalid({ [key]: 'Выберите допустимое значение' });
    const row = c.byCode(app, target, code, false);
    params[key] = row ? row.id : '__missing__';
    conditions.push(multiple ? 'EXISTS (SELECT 1 FROM json_each(' + field + ') WHERE value = {:' + key + '})'
      : field + ' = {:' + key + '}');
  };
  if (kind === 'drugs') {
    refFilter('categoryId', 'categories', 'categories', true);
    refFilter('manufacturerId', 'manufacturer', 'manufacturers'); refFilter('supplierId', 'supplier', 'suppliers');
  }
  if (kind === 'suppliers') refFilter('manufacturerId', 'manufacturers', 'manufacturers', true);
  if (kind === 'licenses') refFilter('supplierId', 'supplier', 'suppliers');
  if ((kind === 'manufacturers' || kind === 'suppliers') && q.country) {
    conditions.push('country = {:country}'); params.country = q.country;
  }
  const yearField = { drugs: 'productionYear', suppliers: 'partnershipYear', licenses: 'expiresYear' }[kind];
  if (yearField) ['yearFrom', 'yearTo'].forEach(key => {
    if (q[key] === undefined) return;
    const year = Number(q[key]);
    if (!Number.isInteger(year) || year < 1900 || year > 2200) c.invalid({ [key]: 'Год от 1900 до 2200' });
    conditions.push(yearField + (key === 'yearFrom' ? ' >= ' : ' <= ') + '{:' + key + '}'); params[key] = year;
  });
  if (params.yearFrom && params.yearTo && params.yearFrom > params.yearTo)
    c.invalid({ yearTo: 'Год окончания диапазона должен быть не меньше начального' });
  if (kind === 'categories' && q.usedOnly === 'true') conditions.push(
    "EXISTS (SELECT 1 FROM drugs, json_each(drugs.categories) WHERE drugs.deletedAt = '' AND value = categories.id)");
  const sql = conditions.length ? conditions.join(' AND ') : '1';
  const total = c.count(app, kind, sql, params);
  const size = [10, 25, 50].includes(Number(q.size)) ? Number(q.size) : 10;
  const requested = Number(q.page);
  const page = Math.min(Math.max(1, Math.ceil(total / size)), Number.isSafeInteger(requested) && requested > 0 ? requested : 1);
  const fields = {
    drugs: { name: 'name', year: 'productionYear', price: 'price', stock: 'stock' },
    suppliers: { name: 'name', year: 'partnershipYear', country: 'country', email: 'email' },
    manufacturers: { name: 'name', country: 'country', email: 'contactEmail' },
    categories: { name: 'name', description: 'description' },
    licenses: { name: 'number', issuedYear: 'issuedYear', expiresYear: 'expiresYear' },
  };
  const sort = String(q.sort || 'name,asc').split(',');
  const field = sort[0] === 'id' ? 'code' : Object.prototype.hasOwnProperty.call(fields[kind], sort[0])
    ? fields[kind][sort[0]] : fields[kind].name;
  const direction = sort[1] === 'desc' ? ' DESC' : ' ASC';
  const result = arrayOf(new Record(app.findCollectionByNameOrId(kind)));
  app.recordQuery(kind).andWhere($dbx.exp(sql, params)).orderBy(field + direction, 'code' + direction)
    .limit(size).offset((page - 1) * size).all(result);
  return { items: Array.from(result).map(row => c.dto(app, kind, row)), total, size, page };
}
module.exports = { save, remove, restore, list };
