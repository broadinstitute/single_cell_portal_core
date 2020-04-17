/* eslint-disable */
// ESLint unexpectedly converts use `done` in `it` to a Promise, so disable it

import React from 'react'
import { mount } from 'enzyme'
// import { act } from 'react-dom/test-utils';

const fetch = require('node-fetch')

import DownloadButton from 'components/search/controls/DownloadButton'
import * as UserProvider from 'providers/UserProvider'
import * as StudySearchProvider
  from 'providers/StudySearchProvider'
import * as DownloadProvider
  from 'providers/DownloadProvider'

describe('Download components for faceted search', () => {
  beforeAll(() => {
    global.fetch = fetch

    const userContext = { accessToken: 'test' }
    const studySearchContext = {
      results: { matchingAccessions: ['SCP1', 'SCP2'] },
      params: {
        terms: 'test',
        facets: {},
        page: 1
      }
    }
    const downloadContext = {
      downloadSize: {
        metadata: { total_bytes: 200, total_files: 2 },
        expression: { total_bytes: 201, total_files: 3 },
        isLoaded: true
      },
      params: {
        terms: 'test',
        facets: {},
        page: 1
      }
    }

    jest.spyOn(UserProvider, 'useContextUser')
      .mockImplementation(() => {
        return userContext
      })

    jest.spyOn(StudySearchProvider, 'useContextStudySearch')
      .mockImplementation(() => {
        return studySearchContext
      })

    jest.spyOn(DownloadProvider, 'useContextDownload')
      .mockImplementation(() => {
        return downloadContext
      })
  })

  it('shows Download button', async () => {
    const wrapper = mount((< DownloadButton />))
    expect(wrapper.find('DownloadButton')).toHaveLength(1)
  })

  it('shows expected tooltip for unauthenticated users', async () => {

    const userContext = { accessToken: '' } // as when unauthenticated
    jest.spyOn(UserProvider, 'useContextUser')
      .mockImplementation(() => {
        return userContext
      })

    const wrapper = mount((< DownloadButton />))
    wrapper.find('#download-button > span').simulate('mouseenter')

    const tooltipHint =
      wrapper.find('OverlayTrigger').prop('overlay').props['children']

    expect(tooltipHint).toBe('To download, please sign in')
  })

  // TODO (SCP-2333): Restore test for showing modal upon clicking Download button
  // it('shows modal upon clicking Download button', done => {
  //   const wrapper = mount(<DownloadButton />)

  //   // To consider: Having to call "wrapper.find('Modal').first()" is tedious,
  //   // but assigning it to a variable fails to capture updates.  Find a
  //   // more succinct approach that captures updates.
  //   expect(wrapper.find('Modal').first().prop('show')).toEqual(false)
  //   // act(() => {
  //     wrapper.find('#download-button > span').simulate('click')
  //     console.log('in download.test.js, after click')
  //     // wrapper.update();

  //     expect(wrapper.find('Modal').first().prop('show')).toEqual(true)
  //     console.log('in download.test.js, done')
  //     done()
  //   // })
  // })
})
