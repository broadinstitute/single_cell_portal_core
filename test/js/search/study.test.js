import React from 'react'
import * as ReactAll from 'react'
import { render } from '@testing-library/react'

import StudySearchResult from 'components/search/results/StudySearchResult'

const facetMatchedStudy = {
  name: 'Tuberculosis subtypes in human male blood',
  description: 'stuff and things',
  cell_count: 130,
  metadata: {
    'species': ['Homo sapiens'],
    'disease': ['tuberculosis'],
    'organ': ['lung', 'blood']
  },
  facet_matches: {
    facet_search_weight: 1,
    organ: [{ id: 'id1', name: 'blood' }]
  }
}

const complexFacetMatchedStudy = {
  name: 'Tuberculosis subtypes in human male blood',
  description: 'stuff and things',
  cell_count: 130,
  metadata: {
    'species': ['Homo sapiens'],
    'disease': ['tuberculosis'],
    'organ': ['lung', 'blood']
  },
  facet_matches: {
    facet_search_weight: 1,
    organ: [{ id: 'id1', name: 'blood' }],
    species: [{ id: 'id5', name: 'mouse' }, { id: 'id7', name: 'human' }]
  }
}

const numericFacetMatchedStudy = {
  name: 'Tuberculosis subtypes in human male blood',
  description: 'stuff and things',
  cell_count: 130,
  metadata: {
    'species': ['Homo sapiens'],
    'disease': ['tuberculosis'],
    'organ': ['lung', 'blood']
  },
  facet_matches: {
    facet_search_weight: 1,
    organism_age: [{ min: 30, max: 50, unit: 'years' }]
  }
}

const numericFacetMatchedRange0Study = {
  name: 'Tuberculosis subtypes in human male blood',
  description: 'stuff and things',
  metadata: {
    'species': ['Homo sapiens'],
    'disease': ['tuberculosis'],
    'organ': ['lung', 'blood']
  },
  cell_count: 130,
  facet_matches: {
    facet_search_weight: 1,
    organism_age: [{ min: 0, max: 50, unit: 'years' }]
  }
}

const facetUnmatchedStudy = {
  name: 'Tuberculosis subtypes in human male blood',
  description: 'stuff and things',
  metadata: {}
}

describe('Facet match badges', () => {
  it('renders no badges with no matches', async () => {
    const { container } = render((
      <StudySearchResult study={facetUnmatchedStudy}/>
    ))
    expect(container.getElementsByClassName('facet-match')).toHaveLength(0)
  })

  it('renders one badges with one match', async () => {
    const { container } = render((
      <StudySearchResult study={facetMatchedStudy}/>
    ))
    expect(container.getElementsByClassName('facet-match')).toHaveLength(1)
    expect(container.getElementsByClassName('facet-match')[0].textContent.trim()).toEqual('blood')
  })

  it('renders two badges with two matches', async () => {
    const { container } = render((
      <StudySearchResult study={complexFacetMatchedStudy}/>
    ))
    expect(container.getElementsByClassName('facet-match')).toHaveLength(2)
    expect(container.getElementsByClassName('facet-match')[0].textContent.trim()).toEqual('blood')
    expect(container.getElementsByClassName('facet-match')[1].textContent.trim()).toEqual('mouse, human')
  })

  it('renders badges for numeric facets', async () => {
    const { container } = render((
      <StudySearchResult study={numericFacetMatchedStudy}/>
    ))
    expect(container.getElementsByClassName('facet-match')).toHaveLength(1)
    expect(container.getElementsByClassName('facet-match')[0].textContent.trim()).toEqual('organism age 30-50 years')
    const { container: container2 } = render((
      <StudySearchResult study={numericFacetMatchedRange0Study}/>
    ))
    expect(container2.getElementsByClassName('facet-match')).toHaveLength(1)
    expect(container2.getElementsByClassName('facet-match')[0].textContent.trim()).toEqual('organism age 0-50 years')
  })
})
