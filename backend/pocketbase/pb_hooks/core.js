'use strict';

const kinds = ['drugs', 'suppliers', 'manufacturers', 'categories', 'licenses'];
function fail(status, message, errors) {
  const error = new Error(message);
  error.status = status;
  error.errors = errors;
  throw error;
}
function invalid(errors) { fail(422, 'Проверьте поля формы.', errors); }
function first(app, kind, filter, params = {}) {
  const rows = app.findRecordsByFilter(kind, filter, '', 1, 0, params);
  return rows.length ? rows[0] : null;
}
function byCode(app, kind, code, required = true) {
  if (!Number.isInteger(code) || code < 1) {
    if (required) fail(404, 'Некорректный код записи.');
    return null;
  }
  const row = first(app, kind, 'code = {:code}', { code });
  if (!row && required) fail(404, 'Запись не найдена.');
  return row;
}
function byId(app, kind, id) {
  if (!id) return null;
  return first(app, kind, 'id = {:id}', { id });
}
function active(row) { return row && !row.getString('deletedAt'); }
function nextCode(app, kind) {
  let sequence = first(app, 'pharmacy_config', 'name = {:name}', { name: 'sequence-' + kind });
  if (!sequence) {
    sequence = new Record(app.findCollectionByNameOrId('pharmacy_config'));
    sequence.set('name', 'sequence-' + kind);
  }
  // Also supports explicitly numbered records created by the superuser in the dashboard.
  const last = app.findRecordsByFilter(kind, '', '-code', 1, 0);
  const code = Math.max(sequence.getInt('counter'), last.length ? last[0].getInt('code') : 0) + 1;
  sequence.set('counter', code);
  app.save(sequence);
  return code;
}
function iso(value) { return value ? new Date(value).toISOString() : null; }
function dto(app, kind, row, expand = true) {
  if (!row) return null;
  const result = { id: row.getInt('code'), deletedAt: iso(row.getString('deletedAt')) };
  const fields = {
    drugs: ['name', 'registrationNumber', 'productionYear', 'price', 'stock'],
    suppliers: ['name', 'contactPerson', 'country', 'phone', 'email', 'partnershipYear'],
    manufacturers: ['name', 'country', 'contactEmail'],
    categories: ['name', 'description'], licenses: ['number', 'issuedYear', 'expiresYear'],
  };
  fields[kind].forEach(key => {
    result[key] = ['productionYear', 'price', 'stock', 'partnershipYear', 'issuedYear', 'expiresYear'].includes(key)
      ? row.getFloat(key) : row.getString(key);
  });
  const related = (target, id) => dto(app, target, byId(app, target, id), false);
  if (kind === 'drugs') {
    result.manufacturer = related('manufacturers', row.getString('manufacturer'));
    result.supplier = related('suppliers', row.getString('supplier'));
    result.categories = Array.from(row.getStringSlice('categories')).map(id => related('categories', id)).filter(Boolean);
  } else if (kind === 'suppliers') {
    result.manufacturers = Array.from(row.getStringSlice('manufacturers')).map(id => related('manufacturers', id)).filter(Boolean);
    if (expand) result.license = dto(app, 'licenses', first(app, 'licenses', 'supplier = {:id}', { id: row.id }), false);
  } else if (kind === 'licenses') {
    // Keep the foreign key for nested license DTOs as well as standalone records.
    const supplier = byId(app, 'suppliers', row.getString('supplier'));
    result.supplierId = supplier ? supplier.getInt('code') : 0;
    if (expand) result.supplier = dto(app, 'suppliers', supplier, false);
  }
  return result;
}
function rows(app, kind, filter = '', params = {}) {
  return app.findRecordsByFilter(kind, filter, kind === 'pharmacy_sessions' ? 'startedAt' : 'code', 0, 0, params);
}
function count(app, kind, sql = '1', params = {}) {
  return app.countRecords(kind, $dbx.exp(sql, params));
}
module.exports = { kinds, fail, invalid, first, byCode, byId, active, nextCode, iso, dto, rows, count };
