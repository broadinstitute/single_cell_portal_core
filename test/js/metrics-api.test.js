// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

const fetch = require('node-fetch')
import { screen, render, fireEvent } from '@testing-library/react'
import React from 'react';

import {logClick, logClickLink, logMenuChange, setMetricsApiMockFlag} from 'lib/metrics-api'
import {logToSentry} from 'lib/sentry-logging'
import * as SCPContextProvider from '~/providers/SCPContextProvider'
import * as Sentry from '@sentry/react'

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
    // Fake the `fetch()`because we want to intercept the outgoing request
    global.fetch = jest.fn(() =>
      Promise.resolve({
        json: () => Promise.resolve({})
      })
    )

    render(<a href="#" onClick={(e) => logClick(e)}>Text that is linked</a>)
    fireEvent.click(screen.getByText('Text that is linked'))

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
    // Fake the `fetch()`because we want to intercept the outgoing request

    global.fetch = jest.fn(() =>
      Promise.resolve({
        json: () => Promise.resolve({})
    }))

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
    // Fake the `fetch()`because we want to intercept the outgoing request
    global.fetch = jest.fn(() =>
      Promise.resolve({
        json: () => Promise.resolve({})
    }))

    const target = {
        classList: ['class-name-1', 'class-name-2'],
        innerText: 'dif Text that is linked',
        id: "link-id",
        dataset: {},
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

  it('appropriately determines whether to log to Sentry', () => {

    console.log = jest.fn();

    // Mimic a logged environment
    jest
      .spyOn(SCPContextProvider, 'getSCPContext')
      .mockReturnValue({environment: 'staging'})

    // Almost no events should be suppressed from Sentry with sampleRate = 0.99
    let sampleRate = 0.99
    for (let i = 0; i < 100; i++) {
      logToSentry({}, true, sampleRate)
    }
    const numDroppedInHighSampleRate = console.log.mock.calls.length
    expect(numDroppedInHighSampleRate).toBeLessThan(20)

    // Almost all events should be suppressed from Sentry with sampleRate = 0.01
    sampleRate = 0.01
    for (let i = 0; i < 100; i++) {
      logToSentry({}, true, sampleRate)
    }
    const numDroppedInLowSampleRate = console.log.mock.calls.length - numDroppedInHighSampleRate
    expect(numDroppedInLowSampleRate).toBeGreaterThan(80)

    // Test warnings for throttling with a response object
    for (let i = 0; i < 100; i++) {
      logToSentry({url: 'foo://bar.baz'}, true, sampleRate)
    }
    const numDroppedInLowSampleWithResponse = console.log.mock.calls.length
    const latestWarning = console.log.mock.calls.slice(-1)[0][0]
    expect(latestWarning.url).toEqual('foo://bar.baz')

    // Nothing should be logged when Sentry is suppressed, and we expect warnings of this
    jest
      .spyOn(SCPContextProvider, 'getSCPContext')
      .mockReturnValue({environment: 'test'})
    logToSentry({})
    const numDroppedWhenSuppressed = console.log.mock.calls.length - numDroppedInLowSampleWithResponse
    expect(numDroppedWhenSuppressed).toEqual(1)

    // Nothing should be logged when level is info
    jest
      .spyOn(SCPContextProvider, 'getSCPContext')
      .mockReturnValue({level: 'info'})
    logToSentry({})
    const numDroppedWhenInfo = console.log.mock.calls.length - numDroppedInLowSampleWithResponse
    expect(numDroppedWhenInfo).toEqual(1)
  })

})
