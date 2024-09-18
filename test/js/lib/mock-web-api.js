/** @fileoverview Mock for the Cache interface of the Web API
 *
 * https://developer.mozilla.org/en-US/docs/Web/API/Cache
*/

export const mockCaches = {
  _cacheStores: {},

  open: jest.fn((cacheName) => {
    console.log('cacheName', cacheName)
    // Initialize the store for the cache name if it doesn't exist
    if (!mockCaches._cacheStores[cacheName]) {
      mockCaches._cacheStores[cacheName] = {};
    }

    console.log('mockCaches._cacheStores[cacheName]', mockCaches._cacheStores[cacheName])

    return Promise.resolve({
      add: jest.fn((request) => {
        const response = new Response(`Response for ${request.url}`); // Mocking a response
        return mockCaches.put(request, response, cacheName);
      }),
      addAll: jest.fn((requests) => {
        const responses = requests.map(req => new Response(`Response for ${req.url}`));
        return Promise.all(responses.map((response, index) => {
          return mockCaches.put(requests[index], response, cacheName);
        }));
      }),
      delete: jest.fn((request) => {
        const key = request.url || request;
        if (mockCaches._cacheStores[cacheName][key]) {
          delete mockCaches._cacheStores[cacheName][key];
          return Promise.resolve(true);
        }
        return Promise.resolve(false);
      }),
      match: jest.fn((request) => {
        const key = request.url || request;
        return Promise.resolve(mockCaches._cacheStores[cacheName][key] || undefined);
      }),
      put: jest.fn((request, response) => {
        console.log('in put, cacheName, request', cacheName, request)
        const key = request.url || request;
        mockCaches._cacheStores[cacheName][key] = response;
        return Promise.resolve();
      }),
      keys: jest.fn(() => {
        console.log('in keys, mockCaches._cacheStores', mockCaches._cacheStores)
        return Promise.resolve(Object.keys(mockCaches._cacheStores[cacheName]).map(key => new Request(key)));
      }),
    });
  }),

  match: jest.fn((request, cacheName) => {
    const key = request.url || request;
    return Promise.resolve(mockCaches._cacheStores[cacheName]?.[key] || null);
  }),

  delete: jest.fn((request, cacheName) => {
    const key = request.url || request;
    if (mockCaches._cacheStores[cacheName] && mockCaches._cacheStores[cacheName][key]) {
      delete mockCaches._cacheStores[cacheName][key];
      return Promise.resolve(true);
    }
    return Promise.resolve(false);
  }),

  keys: jest.fn(() => {
    // Collect all cache keys across all cache stores
    console.log('in mockCaches._cacheStores', mockCaches._cacheStores)
    return Promise.resolve(Object.keys(mockCaches._cacheStores).flatMap(cacheName =>
      Object.keys(mockCaches._cacheStores[cacheName]).map(key => new Request(key))
    ));
  }),
};
