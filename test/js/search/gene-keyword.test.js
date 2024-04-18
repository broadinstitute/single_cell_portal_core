import React from 'react'

import { render, fireEvent } from '@testing-library/react'

import { PropsStudySearchProvider } from 'providers/StudySearchProvider'
import GeneKeyword from 'components/search/genes/GeneKeyword'
import { GeneSearchContext } from 'providers/GeneSearchProvider'
import * as Reach from '@reach/router'

describe('Search query display text', () => {
  const locationMock = jest.spyOn(Reach, 'useLocation')

  it('shows blank search form with place holder text present', async () => {
    locationMock.mockImplementation(() => (
      { pathname: "/single_cell/app/genes", search: '' }
    ))
    const { container } = render((
      <GeneKeyword placeholder={'I am a place holder'} />
    ))
    expect(container.querySelector('.gene-keyword-search').textContent.trim()).toEqual('I am a place holder')
  })

  it('shows study result matches search param', async () => {
    locationMock.mockImplementation(() => (
      { pathname: "/single_cell/app/genes", search: 'genes=PTEN' }
    ))
    const searchState = {
      params: {
        genes: 'PTEN',
        genePage: 1
      },
      results: [],
      isLoading: false,
      isLoaded: false,
      isError: false
    }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: 'PTEN', page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneKeyword placeholder={'I am a place holder'} />
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))
    expect(container.querySelector('.gene-keyword-search').textContent.trim()).toEqual('PTEN')
  })

  it('show matching multiple params and strips off surronding quotes on search params', async () => {
    locationMock.mockImplementation(() => (
      { pathname: "/single_cell/app/genes", search: 'genes=PTEN,NA' }
    ))
    const searchState = {
      params: {
        genes: 'PTEN, NA',
        genePage: 1
      },
      results: [],
      isLoading: false,
      isLoaded: false,
      isError: false
    }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '"PTEN", NA', page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneKeyword placeholder={'I am a place holder'} />
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))
    expect(container.querySelector('.gene-keyword-search').textContent.trim()).toEqual('PTEN,NA')
  })

  it('show that searching on no entered genes provides the generic results ', async () => {
    locationMock.mockImplementation(() => (
      { pathname: "/single_cell/app/genes", search: '' }
    ))
    const searchState = {
      params: {
        genes: '',
        genePage: 1
      },
      results: [],
      isLoading: false,
      isLoaded: false,
      isError: false
    }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneKeyword placeholder={'I am a place holder'} />
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))
    expect(container.querySelector('.gene-keyword-search').textContent.trim()).toEqual('I am a place holder')
    fireEvent.click(container.querySelector('.gene-keyword-search'))
    expect(container.querySelector('.gene-keyword-search').textContent.trim()).toEqual('I am a place holder')
  })
})

