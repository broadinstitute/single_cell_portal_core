// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

const fetch = require('node-fetch')
import scpApi, {
  fetchAuthCode, fetchFacetFilters, defaultInit
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

  it('returns `authCode` and `timeInterval` from fetchAuthCode', async () => {
    const { authCode, timeInterval } = await fetchAuthCode()
    expect(authCode).toBe(123456)
    expect(timeInterval).toBe(1800)
  })

  it('returns 10 filters from fetchFacetFilters', async () => {
    const apiData = await fetchFacetFilters('disease', 'tuberculosis')
    expect(apiData.filters).toHaveLength(10)
  })

  it('includes perfTime in return from scpApi', async () => {

    const [authCode, perfTime] =
      await scpApi('/search/auth_code', defaultInit(), true)

    expect(Number.isInteger(perfTime)).toEqual(true);
    expect(perfTime).toBeGreaterThan(0);
  });
})
