/* eslint-disable no-tabs */
/**
 * @fileoverview Tests for bookmarks functionality
 */

import * as Reach from '@reach/router'
import React from 'react'
import { render, fireEvent, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import * as UserProvider from '~/providers/UserProvider'
import BookmarkManager from 'components/bookmarks/BookmarkManager'
import * as ScpApi from 'lib/scp-api'
import _cloneDeep from 'lodash/cloneDeep'

describe('Bookmarks manager', () => {
  const bookmarks = [
    {
      'id' : '65c5571794ec8f2b83bb7640',
      'name': 'tSNE',
      'path': '/single_cell/study/SCP1234?cluster=tSNE&annotation=louvain--group--study&subsample=all',
      'description': 'Default annotation'
    }
  ]
  const clearExploreParams = jest.fn()
  const routerNav = jest.spyOn(Reach, 'navigate')
  routerNav.mockImplementation(() => {})
  const locationMock = jest.spyOn(Reach, 'useLocation')
  locationMock.mockImplementation(() => (
    { pathname: "/single_cell/study/SCP1234", search: '' }
  ))

  it('shows login popover', async () => {
    jest.spyOn(UserProvider, 'isUserLoggedIn').mockReturnValue(false)
    const clearExploreParams = jest.fn()

    const { container } = render(
      <BookmarkManager bookmarks={[]} clearExploreParams={clearExploreParams} />
    )
    const bookmarkManager = container.querySelector('#bookmark-manager')
    expect(bookmarkManager).toBeInTheDocument()
    fireEvent.click(bookmarkManager)
    expect(await screen.getByText('You must sign in to bookmark this view')).toBeVisible()
  })

  it('shows bookmark form', async () => {
    jest.spyOn(UserProvider, 'isUserLoggedIn').mockReturnValue(true)

    const { container } = render(
      <BookmarkManager bookmarks={bookmarks} clearExploreParams={clearExploreParams} />
    )
    const bookmarkManager = container.querySelector('#bookmark-manager')
    expect(bookmarkManager).toBeInTheDocument()
    fireEvent.click(bookmarkManager)
    expect(await screen.queryByLabelText('Bookmark name')).toBeVisible()
  })

  it('shows all bookmarks', async () => {
    jest.spyOn(UserProvider, 'isUserLoggedIn').mockReturnValue(true)
    jest.spyOn(ScpApi, 'fetchBookmarks').mockImplementation(params => {
      const response = _cloneDeep(bookmarks)
      return Promise.resolve(response)
    })

    const { container } = render(
      <BookmarkManager bookmarks={bookmarks} clearExploreParams={clearExploreParams} />
    )
    const bookmarkManager = container.querySelector('#bookmark-manager')
    fireEvent.click(bookmarkManager)
    const allBookarks = await screen.getByText('See bookmarks')
    fireEvent.click(allBookarks)
    const modal = await screen.getByTestId('bookmarks-list-modal')
    expect(modal).toBeVisible()
    expect(modal.querySelectorAll('.bookmarks-list-item').length).toBe(1)
  })
})
