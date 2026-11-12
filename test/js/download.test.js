/* eslint-disable */
// ESLint unexpectedly converts use `done` in `it` to a Promise, so disable it

import React from 'react'
import { render, fireEvent, screen } from '@testing-library/react'
import '@testing-library/jest-dom'
// import { act } from 'react-dom/test-utils';

const fetch = require('node-fetch')

import DownloadButton from 'components/search/controls/download/DownloadButton'
import { UserContext } from 'providers/UserProvider'


describe('Download components for faceted search', () => {
  beforeAll(() => {
    global.fetch = fetch
  })

  // Note: tests that mock global.fetch must be cleared after every test
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })

  it('shows expected tooltip for unauthenticated users', async () => {
    const { container } = render((
      <UserContext.Provider value={{ accessToken: ''}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: 'foo', facets: [] }}/>
      </UserContext.Provider>
    ))
    const button = container.querySelector('#download-button')
    expect(button.disabled).toEqual(true)
    fireEvent.mouseOver(container.querySelector('span'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('To download, please sign in')
  })

  it('shows expected tooltip if no search has been performed', async () => {
    const { container } = render((
      <UserContext.Provider value={{ accessToken: 'test'}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: '', facets: [] }}/>
      </UserContext.Provider>
    ))
    const button = container.querySelector('#download-button')
    expect(button.disabled).toEqual(true)
    fireEvent.mouseOver(container.querySelector('span'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('To download, first do a search that returns results')
  })

  it('is enabled and shows the modal for signed in users who perform a search', async () => {
    // mock request to prevent TypeError: response.json is not a function error
    const mockSuccessResponse = {}
    const mockJsonPromise = Promise.resolve(mockSuccessResponse)
    const mockFetchPromise = Promise.resolve({
      ok: true,
      json: () => {
        mockJsonPromise
      }
    })
    jest.spyOn(global, 'fetch').mockImplementation(() => mockFetchPromise)

    const { container } = render((
      <UserContext.Provider value={{ accessToken: 'test'}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: 'foo', facets: [] }}/>
      </UserContext.Provider>
    ))
    const button = container.querySelector('#download-button')
    expect(button.disabled).toEqual(false)
    fireEvent.click(button)
    // bootstrap puts
    expect(screen.getAllByRole('dialog')).toHaveLength(2)
  })
})
