/* eslint-disable require-jsdoc */
/** @fileoverview Node port for interfaces of Web API; helps mocking
 *
 * https://developer.mozilla.org/en-US/docs/Web/API/Cache
*/
const { Readable } = require('stream')

export const nodeCaches = {
  _cacheStores: {},

  open: jest.fn(cacheName => {
    // Initialize the store for the cache name if it doesn't exist
    if (!nodeCaches._cacheStores[cacheName]) {
      nodeCaches._cacheStores[cacheName] = {}
    }

    return Promise.resolve({
      add: jest.fn(request => {
        const response = new Response(`Response for ${request.url}`)
        return nodeCaches.put(request, response, cacheName)
      }),
      addAll: jest.fn(requests => {
        const responses = requests.map(req => new Response(`Response for ${req.url}`))
        return Promise.all(responses.map((response, index) => {
          return nodeCaches.put(requests[index], response, cacheName)
        }))
      }),
      delete: jest.fn(request => {
        const key = request.url || request
        if (nodeCaches._cacheStores[cacheName][key]) {
          delete nodeCaches._cacheStores[cacheName][key]
          return Promise.resolve(true)
        }
        return Promise.resolve(false)
      }),
      match: jest.fn(request => {
        const key = request.url || request
        return Promise.resolve(nodeCaches._cacheStores[cacheName][key] || undefined)
      }),
      put: jest.fn((request, response) => {
        const key = request.url || request
        nodeCaches._cacheStores[cacheName][key] = response
        return Promise.resolve()
      }),
      keys: jest.fn(() => {
        return Promise.resolve(Object.keys(nodeCaches._cacheStores[cacheName]).map(key => new Request(key)))
      })
    })
  }),

  match: jest.fn((request, cacheName) => {
    const key = request.url || request
    return Promise.resolve(nodeCaches._cacheStores[cacheName]?.[key] || null)
  }),

  delete: jest.fn((request, cacheName) => {
    const key = request.url || request
    if (nodeCaches._cacheStores[cacheName] && nodeCaches._cacheStores[cacheName][key]) {
      delete nodeCaches._cacheStores[cacheName][key]
      return Promise.resolve(true)
    }
    return Promise.resolve(false)
  }),

  keys: jest.fn(() => {
    // Collect all cache keys across all cache stores
    return Object.keys(nodeCaches._cacheStores)
  })
}

export const nodeRequest = class {
  constructor(url, options = {}) {
    this.url = url
    this.method = options.method || 'GET'
    this.headers = new Headers(options.headers)
  }
}

export const nodeResponse = class {
  constructor(body, options = {}) {
    this.status = options.status || 200
    this.ok = this.status >= 200 && this.status < 300
    this.headers = new Headers(options.headers)
    this.bodyUsed = false

    // Ensure the body is a string or Buffer
    const readableBody = typeof body === 'string' ? body : body.toString()

    // Create a ReadableStream
    const stream = new Readable({
      read() {
        this.push(readableBody) // Push the string or buffer into the stream
        this.push(null) // Signal the end of the stream
      },
    })

    this.body = stream // Assign the readable stream to body
  }

  // Define text() method to read from the stream
  async text() {
    if (this.bodyUsed) {
      return Promise.reject(new TypeError('Already read'))
    }
    this.bodyUsed = true
    return new Promise((resolve, reject) => {
      const chunks = []
      this.body.on('data', chunk => {
        chunks.push(chunk)
      })
      this.body.on('end', () => {
        resolve(Buffer.concat(chunks).toString())
      })
      this.body.on('error', (err) => {
        reject(err)
      })
    })
  }

  // You can also implement json() if needed
  async json() {
    const text = await this.text()
    return JSON.parse(text)
  }
}


export const nodeHeaders = class {
  constructor(headers) {
    this.map = new Map()
    if (headers) {
      for (const [key, value] of Object.entries(headers)) {
        this.append(key, value)
      }
    }
  }

  append(key, value) {
    const existingValue = this.map.get(key.toLowerCase())
    if (existingValue) {
      this.map.set(key.toLowerCase(), existingValue + ', ' + value)
    } else {
      this.map.set(key.toLowerCase(), value)
    }
  }

  get(key) {
    return this.map.get(key.toLowerCase()) || null
  }

  has(key) {
    return this.map.has(key.toLowerCase())
  }

  set(key, value) {
    this.map.set(key.toLowerCase(), value)
  }

  delete(key) {
    this.map.delete(key.toLowerCase())
  }

  // Additional methods if needed
}
