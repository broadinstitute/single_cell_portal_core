import React from 'react'
import { render } from '@testing-library/react'
import GeneSearchView from 'components/search/genes/GeneSearchView'
import { PropsStudySearchProvider } from 'providers/StudySearchProvider'
import { GeneSearchContext, emptySearch } from 'providers/GeneSearchProvider'


describe('Gene search page landing', () => {
  it('shows study details when empty', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar' }] }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', facets: {}, page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneSearchView/>
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))
    expect(container.getElementsByClassName('study-label')).toHaveLength(1)
  })

  it('shows gene results when gene query is loaded', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2'] }] }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', facets: {}, page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneSearchView/>
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))

    expect(container.getElementsByClassName('study-label')).toHaveLength(1)
    const wrapperText = container.getElementsByClassName('study-gene-result')[0].textContent
    expect(wrapperText.indexOf('This study contains agpat2 in expression data')).toBeGreaterThan(0)
  })

  it('clears gene queries', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2'] }] }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', facets: {}, page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneSearchView/>
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))

    expect(container.getElementsByClassName('study-label')).toHaveLength(1)
    const wrapperText = container.getElementsByClassName('study-gene-result')[0].textContent
    expect(wrapperText.indexOf('This study contains agpat2 in expression data')).toBeGreaterThan(0)
  })


  it('shows gene results when multigene query is loaded', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2', 'farsa'] }] }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', facets: {}, page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneSearchView/>
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))

    expect(container.getElementsByClassName('study-label')).toHaveLength(1)
    const wrapperText = container.getElementsByClassName('study-gene-result')[0].textContent
    expect(wrapperText.indexOf('This study contains agpat2, farsa in expression data')).toBeGreaterThan(0)
  })
})
