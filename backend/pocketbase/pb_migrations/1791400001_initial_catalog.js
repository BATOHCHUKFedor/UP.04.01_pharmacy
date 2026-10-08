// Initial example catalog only. Applied once, not at every launch. No passwords or sessions.
migrate((app) => {
  const seed = require(__hooks + '/seed.json');
  const catalog = require(__hooks + '/catalog.js');
  const maps = {};
  ['manufacturers', 'categories', 'suppliers', 'licenses', 'drugs'].forEach(kind => {
    maps[kind] = {};
    seed[kind].forEach(source => {
      const body = { ...source };
      if (body.manufacturerIds) body.manufacturerIds = body.manufacturerIds.map(id => maps.manufacturers[id]);
      if (body.manufacturerId) body.manufacturerId = maps.manufacturers[body.manufacturerId];
      if (body.supplierId) body.supplierId = maps.suppliers[body.supplierId];
      if (body.categoryIds) body.categoryIds = body.categoryIds.map(id => maps.categories[id]);
      const row = catalog.save(app, kind, body);
      maps[kind][source.id] = row.getInt('code');
      if (source.deletedAt) { row.set('deletedAt', source.deletedAt); app.save(row); }
    });
  });
});
