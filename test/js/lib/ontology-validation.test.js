const fetch = require('node-fetch')
const { Readable } = require('stream');

import {
  fetchOntologies
} from 'lib/validation/ontology-validation'


describe('Client-side file validation for AnnData', () => {
  beforeAll(() => {
    global.fetch = fetch

    const mockCaches = {
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

    global.caches = mockCaches;

    // Mock Request
    global.Request = class {
      constructor(url, options = {}) {
        this.url = url;
        this.method = options.method || 'GET';
        this.headers = new Headers(options.headers);
      }
    };

    // Mock Response
    global.Response = class {
      constructor(body, options = {}) {
        this.status = options.status || 200;
        this.ok = this.status >= 200 && this.status < 300;
        this.headers = new Headers(options.headers);
        this.bodyUsed = false;

        // Ensure the body is a string or Buffer
        const readableBody = typeof body === 'string' ? body : body.toString();

        // Create a ReadableStream
        const stream = new Readable({
          read() {
            this.push(readableBody); // Push the string or buffer into the stream
            this.push(null); // Signal the end of the stream
          },
        });

        this.body = stream; // Assign the readable stream to body
      }

      // Define text() method to read from the stream
      async text() {
        if (this.bodyUsed) {
          return Promise.reject(new TypeError('Already read'));
        }
        this.bodyUsed = true;
        return new Promise((resolve, reject) => {
          const chunks = [];
          this.body.on('data', (chunk) => {
            chunks.push(chunk);
          });
          this.body.on('end', () => {
            resolve(Buffer.concat(chunks).toString());
          });
          this.body.on('error', (err) => {
            reject(err);
          });
        });
      }

      // You can also implement json() if needed
      async json() {
        const text = await this.text();
        return JSON.parse(text);
      }
    };


    global.Headers = class {
      constructor(headers) {
        this.map = new Map();
        if (headers) {
          for (const [key, value] of Object.entries(headers)) {
            this.append(key, value);
          }
        }
      }

      append(key, value) {
        const existingValue = this.map.get(key.toLowerCase());
        if (existingValue) {
          this.map.set(key.toLowerCase(), existingValue + ', ' + value);
        } else {
          this.map.set(key.toLowerCase(), value);
        }
      }

      get(key) {
        return this.map.get(key.toLowerCase()) || null;
      }

      has(key) {
        return this.map.has(key.toLowerCase());
      }

      set(key, value) {
        this.map.set(key.toLowerCase(), value);
      }

      delete(key) {
        this.map.delete(key.toLowerCase());
      }

      // Additional methods if needed
    }


  })

  it('Parses AnnData headers', async () => {
    const ontologies = await fetchOntologies()
    console.log('ontologies')
    expect(1).toEqual(1)
  })
})
