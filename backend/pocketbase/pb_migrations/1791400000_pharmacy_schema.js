// PocketBase 0.40.5. No down migration: never silently erase a pharmacy database.
migrate((app) => {
  const text = (name, max, required = true) => ({ type: 'text', name, max, required });
  const number = (name, min, max, required = true) =>
    ({ type: 'number', name, min, max, required, onlyInt: true });
  const relation = (name, collection, multiple = false) => ({
    type: 'relation', name, collectionId: collection.id, required: true,
    maxSelect: multiple ? 100 : 1, cascadeDelete: false,
  });
  const base = (name, fields, indexes = [], type = 'base') => {
    const collection = new Collection({
      type, name, fields: type === 'auth' ? [{ type: 'email', name: 'email', required: false }, ...fields] : fields, indexes,
      listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
      ...(type === 'auth' ? { authRule: null, manageRule: null, passwordAuth: { enabled: false } } : {}),
    });
    // Application accounts use a username; do not require an invented email address.
    app.save(collection);
    return collection;
  };
  const catalog = (name, fields, indexes = []) => base(name, [
    number('code', 1, 2147483647), { type: 'date', name: 'deletedAt' },
    text('searchText', 2000, false), ...fields,
  ], [`CREATE UNIQUE INDEX idx_${name}_code ON ${name} (code)`, ...indexes]);
  const manufacturers = catalog('manufacturers', [
    text('name', 120), text('country', 80), { type: 'email', name: 'contactEmail', required: true },
  ]);
  const categories = catalog('categories', [text('name', 100), text('description', 250)]);
  const suppliers = catalog('suppliers', [
    text('name', 120), text('contactPerson', 120), text('country', 80), text('phone', 30),
    { type: 'email', name: 'email', required: true }, text('emailKey', 254),
    number('partnershipYear', 1900, 2100), relation('manufacturers', manufacturers, true),
  ], ['CREATE UNIQUE INDEX idx_suppliers_email ON suppliers (emailKey)']);
  catalog('licenses', [
    relation('supplier', suppliers), text('number', 40), number('issuedYear', 1900, 2100),
    number('expiresYear', 1900, 2200),
  ], ['CREATE UNIQUE INDEX idx_licenses_supplier ON licenses (supplier)']);
  const drugs = catalog('drugs', [
    text('name', 120), text('registrationNumber', 40), text('registrationKey', 40),
    relation('manufacturer', manufacturers), relation('supplier', suppliers),
    relation('categories', categories, true), number('productionYear', 1900, 2100),
    { type: 'number', name: 'price', min: 0.01, max: 10000000, required: true },
    number('stock', 0, 1000000, false),
  ], ['CREATE UNIQUE INDEX idx_drugs_registration ON drugs (registrationKey)']);
  const users = base('pharmacy_users', [
    number('code', 1, 2147483647), text('username', 40), text('usernameKey', 40), text('name', 80),
    { type: 'select', name: 'role', required: true, maxSelect: 1,
      values: ['customer', 'pharmacist', 'admin'] }, { type: 'bool', name: 'active' },
  ], ['CREATE UNIQUE INDEX idx_pharmacy_users_code ON pharmacy_users (code)',
    'CREATE UNIQUE INDEX idx_pharmacy_users_username ON pharmacy_users (usernameKey)'], 'auth');
  base('pharmacy_sessions', [
    relation('user', users), number('startedAt', 1, 9007199254740991),
    number('expiresAt', 1, 9007199254740991), number('lastActivity', 1, 9007199254740991),
    text('refreshHash', 64), text('previousRefreshHash', 64, false), { type: 'bool', name: 'revoked' },
  ], ['CREATE UNIQUE INDEX idx_pharmacy_sessions_refresh ON pharmacy_sessions (refreshHash)']);
  base('pharmacy_reservations', [
    number('code', 1, 2147483647), relation('user', users), relation('drug', drugs),
    text('customerName', 80), text('drugName', 120), number('quantity', 1, 1000000),
    { type: 'select', name: 'status', required: true, maxSelect: 1,
      values: ['reserved', 'completed', 'cancelled'] },
    { type: 'date', name: 'expiresAt', required: true }, { type: 'bool', name: 'extended' },
  ], ['CREATE UNIQUE INDEX idx_pharmacy_reservations_code ON pharmacy_reservations (code)']);
  const config = base('pharmacy_config', [
    text('name', 80), text('value', 500, false), number('counter', 0, 2147483647, false),
  ], ['CREATE UNIQUE INDEX idx_pharmacy_config_name ON pharmacy_config (name)']);
  const secret = new Record(config);
  secret.set('name', 'jwt-secret');
  secret.set('value', $security.randomString(64));
  app.save(secret);
});
