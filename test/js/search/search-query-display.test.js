import React from 'react'
import { mount } from 'enzyme'

const fetch = require('node-fetch')

import SearchQueryDisplay, { ClearAllButton } from 'components/search/results/SearchQueryDisplay'
import { PropsStudySearchProvider } from 'providers/StudySearchProvider'
import KeywordSearch from 'components/search/controls/KeywordSearch'
import FacetControl from 'components/search/controls/FacetControl'


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
  { id: 'cell_type__custom', filters:  [{ id: 'ctc1', name: 'Bergmann' }] }
]

describe('Search query display text', () => {
  it('renders a single facet', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={oneStringFacet} terms={''}/>
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('Metadata contains (species: Homo sapiens)')
  })

  it('renders multiple facets', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={twoStringFacets} terms={''}/>
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('Metadata contains (disease: disease1) AND (species: Homo sapiens)')
  })

  it('renders string and numeric facets', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={stringAndNumericFacets} terms={''}/>
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('Metadata contains (species: Homo sapiens OR Mus musculus) AND (organism age: 14 - 180 years)')
  })

  it('renders terms', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={[]} terms={['foo']}/>
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('Text contains (foo)')
  })

  it('renders terms and a single facet', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={oneStringFacet} terms={['foo', 'bar']}/>
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('(Text contains (foo OR bar)) AND (Metadata contains (species: Homo sapiens))')
  })

  it('renders or-ed facets properly', async () => {
    const wrapper = mount((
      <SearchQueryDisplay facets={orFacets} />
    ))
    expect(wrapper.find('.query-text').text().trim()).toEqual('Metadata contains ((cell type: amarcrine OR retinal) OR (cell type custom: Bergmann))')
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
      ],
      links: []
    }
    const component = <PropsStudySearchProvider searchParams={{ terms: 'foo', facets: { species: ['NCBITaxon_9606'] } }}>
      <ClearAllButton/>
      <KeywordSearch/>
      <FacetControl facet={speciesFacet}/>
    </PropsStudySearchProvider>
    const wrapper = mount(component)
    expect(wrapper.find('input[name="keywordText"]').first().props().value).toEqual('foo')
    wrapper.find('#facet-species > a').simulate('click')
    // Filter is checked
    expect(wrapper.find('input[name="NCBITaxon_9606"]').props().checked).toEqual(true)
    wrapper.find(ClearAllButton).simulate('click')
    expect(wrapper.find('input[name="keywordText"]').first().props().value).toEqual('')
    // Check if badge for filter doesn't exist
    expect(wrapper.find('.filter-badge-list')).toHaveLength(0)
    // Filter should not be checked
    expect(wrapper.find('input[name="NCBITaxon_9606"]').props().checked).toEqual(false)
  })
})
