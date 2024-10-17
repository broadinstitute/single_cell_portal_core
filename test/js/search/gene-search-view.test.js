import React from 'react'
import * as Reach from '@reach/router'
import { render, screen } from '@testing-library/react'
import GeneSearchView from 'components/search/genes/GeneSearchView'
import { PropsStudySearchProvider } from 'providers/StudySearchProvider'
import { GeneSearchContext, emptySearch } from 'providers/GeneSearchProvider'
import '@testing-library/jest-dom/extend-expect'


describe('Gene search page landing', () => {
  const locationMock = jest.spyOn(Reach, 'useLocation')
  locationMock.mockImplementation(() => (
    { pathname: "/single_cell/app/genes", search: '' }
  ))
  it('shows study details when empty', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar', metadata: {} }] }
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
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2'], metadata: {} }] }
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

  it('shows metadata results when gene query is loaded', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = {
      studies: [
        {
          name: 'foo',
          accession: 'SCP1234',
          description: 'bar',
          gene_matches: ['agpat2'],
          metadata: {
            species: ['Homo sapiens'],
            disease: ['tuberculosis'],
            organ: ['lung', 'blood'],
            sex: ['male'],
            library_preparation_protocol: ['Drop-seq']
          }
        }
      ]
    }
    const { container } = render((
      <PropsStudySearchProvider searchParams={{ terms: '', facets: {}, page: 1 }}>
        <GeneSearchContext.Provider value={searchState}>
          <GeneSearchView/>
        </GeneSearchContext.Provider>
      </PropsStudySearchProvider>
    ))

    expect(screen.getByTestId('SCP1234-cohort-metadata')).toBeInTheDocument()
    expect(container.getElementsByClassName('study-metadata-entry')).toHaveLength(6)
  })

  it('clears gene queries', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2'], metadata: {} }] }
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
    searchState.results = { studies: [{ name: 'foo', description: 'bar', gene_matches: ['agpat2', 'farsa'], metadata: {} }] }
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
