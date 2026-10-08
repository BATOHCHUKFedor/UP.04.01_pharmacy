// Handlers are isolated by PocketBase: require the module INSIDE each callback.
routerAdd('GET', '/api/pharmacy/{path...}', (e) => {
  return require(__hooks + '/api.js').handle(e);
}, $apis.bodyLimit(1048576));
routerAdd('POST', '/api/pharmacy/{path...}', (e) => {
  return require(__hooks + '/api.js').handle(e);
}, $apis.bodyLimit(1048576));
routerAdd('PUT', '/api/pharmacy/{path...}', (e) => {
  return require(__hooks + '/api.js').handle(e);
}, $apis.bodyLimit(1048576));
routerAdd('DELETE', '/api/pharmacy/{path...}', (e) => {
  return require(__hooks + '/api.js').handle(e);
}, $apis.bodyLimit(1048576));
