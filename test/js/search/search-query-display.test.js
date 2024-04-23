import React from 'react'
import { render, screen, fireEvent } from '@testing-library/react'

const fetch = require('node-fetch')

import SearchQueryDisplay, { ClearAllButton } from 'components/search/results/SearchQueryDisplay'
import { PropsStudySearchProvider } from 'providers/StudySearchProvider'
import KeywordSearch from 'components/search/controls/KeywordSearch'
import FacetControl from 'components/search/controls/FacetControl'
import * as Reach from '@reach/router'


const oneStringFacet = [
  { id: 'species', filters: [{ id: 'NCBITaxon_9606', name: 'Homo sapiens' }] }
]

const twoStringFacets = [
  { id: 'disease', filters: [{ id: 'id1', name: 'disease1' }] },
  { id: 'species', filters: [{ id: 'NCBITaxon_9606', name: 'Homo sapiens' }] }
]

const stringAndNumericFacets = [
  {
    id: 'species', filters: [
      { id: 'NCBITaxon_9606', name: 'Homo sapiens' },
      { id: 'NCBITaxon_10090', name: 'Mus musculus' }
    ]
  },
  { id: 'organism_age', filters: { min: 14, max: 180, unit: 'years' } }
]

const orFacets = [
  {
    id: 'cell_type', filters: [
      { id: 'ct1', name: 'amarcrine' },
      { id: 'ct2', name: 'retinal' }
    ]
  },
  { id: 'cell_type__custom', filters: [{ id: 'ctc1', name: 'Bergmann' }] }
]

const locationMock = jest.spyOn(Reach, 'useLocation')
locationMock.mockImplementation(() => (
  { pathname: "/single_cell/", search: '' }
))

describe('Search query display text', () => {
  it('renders a single facet', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={oneStringFacet} terms={''}/>
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Metadata contains (species: Homo sapiens)')
  })

  it('renders multiple facets', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={twoStringFacets} terms={''}/>
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Metadata contains (disease: disease1) AND (species: Homo sapiens)')
  })

  it('renders string and numeric facets', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={stringAndNumericFacets} terms={''}/>
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Metadata contains (species: Homo sapiens OR Mus musculus) AND (organism age: 14 - 180 years)')
  })

  it('renders terms', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={[]} terms={['foo']}/>
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Text contains: foo')
  })


  it('renders terms including one with mismatched parenthesis', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={[]} terms={['(foo']}/>
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Text contains: (foo')
  })

  it('renders terms and a single facet', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={oneStringFacet} terms={['foo', 'bar']}/>
    ))

    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('(Text contains: foo OR bar) AND (Metadata contains (species: Homo sapiens))')
  })

  it('renders or-ed facets properly', async () => {
    const { container } = render((
      <SearchQueryDisplay facets={orFacets} />
    ))
    expect(container.getElementsByClassName('query-text')[0].textContent.trim()).toEqual('Metadata contains ((cell type: amarcrine OR retinal) OR (cell type custom: Bergmann))')
  })
})

describe('Clearing search query', () => {
  it('clears search params', () => {
    const speciesFacet = {
      name: 'Species',
      id: 'species',
      type: 'string',
      links: [{ name: 'NCBI Taxonomy', url: 'https://foo.tdb' }],
      filters: [
        { id: 'NCBITaxon_9606', name: 'Homo Sapiens' }
      ]
    }
    const component = <PropsStudySearchProvider searchParams={{ terms: 'foo', facets: { species: ['NCBITaxon_9606'] } }}>
      <ClearAllButton/>
      <KeywordSearch/>
      <FacetControl facet={speciesFacet}/>
    </PropsStudySearchProvider>
    const { container } = render(component)
    expect(container.querySelector('input[name="keywordText"]').value).toEqual('foo')
    fireEvent.click(container.querySelector('#facet-species > a'))
    // Filter is checked
    expect(container.querySelector('input[name="NCBITaxon_9606"]').checked).toEqual(true)
    fireEvent.click(screen.getByText('Clear All'))
    expect(container.querySelector('input[name="keywordText"]').value).toEqual('')
    // Check if badge for filter doesn't exist
    expect(container.getElementsByClassName('filter-badge-list')).toHaveLength(0)
    // Filter should not be checked
    expect(container.querySelector('input[name="NCBITaxon_9606"]').checked).toEqual(false)
  })
})
