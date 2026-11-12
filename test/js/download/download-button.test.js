import React from 'react'
import { render, waitForElementToBeRemoved, screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom'

import * as ScpApi from 'lib/scp-api'
import DownloadButton from 'components/search/controls/download/DownloadButton'
import { UserContext } from 'providers/UserProvider'


describe('Download button for faceted search', () => {

  it('shows expected tooltip for unauthenticated users', async () => {
    render((
      <UserContext.Provider value={{ accessToken: ''}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: 'foo', facets: [] }}/>
      </UserContext.Provider>
    ))
    expect(screen.getByRole('button')).toHaveTextContent('Download')
    expect(screen.getByRole('button')).toBeDisabled()
    fireEvent.mouseOver(screen.getByText('Download'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('To download, please sign in')
  })

  it('shows expected tooltip if no search has been performed', async () => {
    render((
      <UserContext.Provider value={{ accessToken: 'test'}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: '', facets: [] }}/>
      </UserContext.Provider>
    ))
    expect(screen.getByRole('button')).toHaveTextContent('Download')
    expect(screen.getByRole('button')).toBeDisabled()
    fireEvent.mouseOver(screen.getByText('Download'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('To download, first do a search that returns results')
  })

  it('is enabled and shows the modal for signed in users who perform a search', async () => {
    const fetchDownloadInfo = jest.spyOn(ScpApi, 'fetchDownloadInfo')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchDownloadInfo.mockImplementation(() => Promise.resolve(
      []
    ))
    render((
      <UserContext.Provider value={{ accessToken: 'test'}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: 'foo', facets: [] }}/>
      </UserContext.Provider>
    ))
    expect(screen.getByRole('button')).toBeEnabled()
    fireEvent.click(screen.getByText('Download'))
    await waitForElementToBeRemoved(() => screen.getByTestId('bulk-download-loading-icon'))
    expect(screen.getAllByRole('dialog')).toHaveLength(2) // even though there is only one dialog, bootstrap gives two different elements the role 'dialog'
    const headings = screen.getAllByRole('heading')
    expect(headings).toHaveLength(2)
    expect(headings[0]).toHaveTextContent('1 Select files')
  })

  it('is enabled for users who perform a facet search', async () => {
    render((
      <UserContext.Provider value={{ accessToken: 'test'}}>
        <DownloadButton searchResults={{ matchingAccessions: ['SCP1', 'SCP2'], terms: '', facets: [{disease: ['foo']}] }}/>
      </UserContext.Provider>
    ))
    expect(screen.getByRole('button')).toBeEnabled()
  })
})
