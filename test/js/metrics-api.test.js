// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

const fetch = require('node-fetch')
import {logClick, logClickLink, logMenuChange, setMetricsApiMockFlag} from 'lib/metrics-api'
import * as UserProvider from 'providers/UserProvider'

describe('Library for client-side usage analytics', () => {
  beforeAll(() => {
    global.fetch = fetch
    setMetricsApiMockFlag(true)
  })
  // Note: tests that mock global.fetch must be cleared after every test
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.resetAllMocks();
  })

  it('includes `authenticated: true` when signed in', done => {
    // Spy on `fetch()` and its contingent methods like `json()`,
    // because we want to intercept the outgoing request
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      json: () => {
        mockJsonPromise
      }
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => {
      mockFetchPromise
    })

    // Mock the user context, to mimic auth'd state
    const userContext = { accessToken: 'test' }
    jest.spyOn(UserProvider, 'useContextUser')
      .mockImplementation(() => {
        return userContext
      })

    const event = {
      target: {
        localName: 'a',
        text: 'Text that is linked'
      }
    }
    logClick(event)

    expect(global.fetch).toHaveBeenCalledWith(
      expect.anything(), // URL
      expect.objectContaining({
        body: expect.stringContaining(
          '\"authenticated\":true'
        )
      })
    )
    process.nextTick(() => {
      done()
    })
  })

  it('logs text of selected option on changing in menu', done => {
    // Spy on `fetch()` and its contingent methods like `json()`,
    // because we want to intercept the outgoing request
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      json: () => {
        mockJsonPromise
      }
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => {
      mockFetchPromise
    })

    // Mock the user context, to mimic auth'd state
    const userContext = { accessToken: 'test' }
    jest.spyOn(UserProvider, 'useContextUser')
      .mockImplementation(() => {
        return userContext
      })

    const event = {
      target: {
        options: {
          0: {text: 'Yes'},
          1: {text: 'No'},
          selectedIndex: 1
        }
      }
    }
    logMenuChange(event)

    expect(global.fetch).toHaveBeenCalledWith(
      expect.anything(), // URL
      expect.objectContaining({
        body: expect.stringContaining(
          '\"text\":\"No\"'
        )
      })
    )
    process.nextTick(() => {
      global.fetch.mockClear();
      done()
    })
  })
  it('logs classList and id when link is clicked', done => {
    // Spy on `fetch()` and its contingent methods like `json()`,
    // because we want to intercept the outgoing request
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      json: () => {
        mockJsonPromise
      }
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => {
      mockFetchPromise
    })

    const target = {
        classList: ['class-name-1', 'class-name-2'],
        text: 'dif Text that is linked',
        id: "link-id"
    }
    logClickLink(target)

    let expected = '\"text\":\"dif Text that is linked\",\"classList\":[\"class-name-1\",\"class-name-2\"],\"id\":\"link-id\"'
    expect(global.fetch).toHaveBeenCalledWith(
      expect.anything(), // URL
      expect.objectContaining({
        body: expect.stringContaining(
          expected
        )
      })
    )
    process.nextTick(() => {
      done()
    })
  })
})
