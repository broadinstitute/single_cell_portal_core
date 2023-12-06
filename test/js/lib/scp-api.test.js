// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/
import CacheMock from 'browser-cache-mock';
import 'isomorphic-fetch';

import scpApi, { fetchSearch, fetchFacetFilters, setupRenewalForReadOnlyToken, setUpRenewalForUserAccessToken } from 'lib/scp-api'
import * as ServiceWorkerCache from 'lib/service-worker-cache'
import * as SCPContextProvider from '~/providers/SCPContextProvider'

const oldWindowLocation = window.location

describe('JavaScript client for SCP REST API', () => {
  // mocking of window.location, from https://www.benmvp.com/blog/mocking-window-location-methods-jest-jsdom/
  delete window.location

  beforeAll(() => {

    window.location = Object.defineProperties(
      {},
      {
        ...Object.getOwnPropertyDescriptors(oldWindowLocation),
        assign: {
          configurable: true,
          value: jest.fn(),
        },
      },
    )

    window.performance = Object.defineProperties(performance, {
      setResourceTimingBufferSize: {
        value: jest.fn(),
        writable: true
      }
    })

    jest.useFakeTimers();
    jest.spyOn(global, 'setTimeout');
  })

  // Note: tests that mock global.fetch must be cleared after every test
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
    jest.spyOn(global, 'setTimeout').mockReset()

  })

  afterAll(() => {
    // restore `window.location` to the `jsdom` `Location` object
    window.location = oldWindowLocation
  })

  it('includes `Authorization: Bearer` in requests when signed in', done => {
    // Spy on `fetch()` and its contingent methods like `json()`,
    // because we want to intercept the outgoing request
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      ok: true,
      json: () => {
        mockJsonPromise
      }
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => mockFetchPromise)

    fetchFacetFilters('disease', 'tuberculosis')
    expect(global.fetch).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          Authorization: 'Bearer test'
        }
      })
    )
    process.nextTick(() => {
      done()
    })
  })

  it('catches 500 errors', async () => {
    expect.assertions(1)
    const mockErrorResponse = {
      json: () => Promise.resolve({
        error: 'Internal Server Error',
      }),
      headers: new Headers({
        'content-type': 'application/json; charset=utf-8'
      })
    }
    jest
      .spyOn(global, 'fetch')
      .mockReturnValue(Promise.resolve(mockErrorResponse))

    return scpApi('/test/path', {}, false)
      .then(() => {})
      .catch(error => {
        expect(error.message).toEqual('Internal Server Error')
      })
  })

  it('catches non-JSON errors', async () => {
    expect.assertions(1)
    const mockErrorResponse = {
      text: () => Promise.resolve(
        'Response that is not JSON, i.e. crudely handled in server'
      ),
      headers: new Headers({
        'content-type': 'text/html; charset=utf-8'
      })
    }
    jest
      .spyOn(global, 'fetch')
      .mockReturnValue(Promise.resolve(mockErrorResponse))

    return scpApi('/test/path', {}, false)
      .then(() => {})
      .catch(error => {
        expect(error.message.includes(
          'Response that is not JSON, i.e. crudely handled in server'
        )).toEqual(true)
      })
  })

  it('leverages service worker cache on fetch, if cache is enabled', async done => {

    const cacheMock = new CacheMock()
    window.caches = {
      open: async () => cacheMock,
      ...cacheMock
    }

    console.debug = jest.fn();

    // Spy on `fetch()` and its contingent methods like `json()`,
    // because we want to intercept the outgoing request
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      ok: true,
      json: () => {
        mockJsonPromise
      },
      clone: () => {}
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => mockFetchPromise)

    jest
      .spyOn(SCPContextProvider, 'getSCPContext')
      .mockReturnValue({
        isServiceWorkerCacheEnabled: true,
        version: '1.21.0'
      })

    jest.spyOn(global, 'fetch').mockImplementation(() => mockFetchPromise)

    jest
      .spyOn(ServiceWorkerCache, 'fetchServiceWorkerCache')

    const type =  'study'
    const searchParams = {page: 1, terms: "", facets: {}}
    await fetchSearch(type, searchParams)

    const url = 'https://localhost:3000/mock_data/search?type=study&page=1.json'
    expect(ServiceWorkerCache.fetchServiceWorkerCache).toHaveBeenCalledWith(
      url,
      expect.objectContaining({
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          Authorization: 'Bearer test'
        }
      })
    )

    done()
  })

  it('sets timer for read only access token renewal', done => {
    window.SCP = {
      readOnlyTokenObject: {
          'access_token': 'ya11.b.foo_bar-baz',
          'expires_in': 3600, // 1 hour in seconds
          'expires_at': '2023-03-28T11:12:02.044-04:00'
      }
    }

    const expectedRenewalTime = 3300 * 1000 // 55 minutes in milliseconds

    setupRenewalForReadOnlyToken('SCP123')
    expect(setTimeout).toHaveBeenCalledTimes(1);
    expect(setTimeout).toHaveBeenLastCalledWith(expect.any(Function), expectedRenewalTime);

    process.nextTick(() => {
      done()
    })
  })

  it('sets timer for user access token renewal', done => {
    window.SCP = {
      userAccessTokenObject: {
          'access_token': 'ya11.b.foo_bar-baz',
          'expires_in': 3600, // 1 hour in seconds
          'expires_at': '2023-03-28T11:12:02.044-04:00'
      }
    }

    const expectedRenewalTime = 3300 * 1000 // 55 minutes in milliseconds

    setUpRenewalForUserAccessToken()
    expect(setTimeout).toHaveBeenCalledTimes(1);
    expect(setTimeout).toHaveBeenLastCalledWith(expect.any(Function), expectedRenewalTime);

    process.nextTick(() => {
      done()
    })
  })

})
