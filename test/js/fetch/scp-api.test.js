// Without disabling eslint code, Promises are auto inserted
/* eslint-disable */

const fetch = require('node-fetch')
import {mockPerformance} from './../mock-performance'
import scpApi, {
  fetchAuthCode, fetchFacetFilters, defaultInit, getFullUrl
} from 'lib/scp-api'

describe('JavaScript client for SCP REST API', () => {
  beforeAll(() => {
    global.fetch = fetch
  })
  // Note: tests that mock global.fetch must be cleared after every test
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })

  it('returns 10 filters from fetchFacetFilters', async () => {
    const apiData = await fetchFacetFilters('disease', 'tuberculosis')
    expect(apiData.filters).toHaveLength(10)
  })

  it('includes `perfTimes` in return from scpApi', async () => {
    const [authCode, perfTimes] =
      await scpApi('/bulk_download/auth_code', defaultInit(), true)

    const perfTime = perfTimes.legacyBackend

    const perfTimeIsFloat =
      !Number.isInteger(perfTime) && (parseFloat(perfTime) === perfTime)

    expect(perfTimeIsFloat).toEqual(true);
    expect(perfTime).toBeGreaterThan(0);
  });
})
