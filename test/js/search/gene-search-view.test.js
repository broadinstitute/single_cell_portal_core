import React from 'react';
import * as ReactAll from 'react';
import { mount } from 'enzyme';
import * as Reach from '@reach/router'

const fetch = require('node-fetch');

import GeneSearchView from 'components/search/genes/GeneSearchView';
import SearchPanel from 'components/search/controls/SearchPanel';
import { PropsStudySearchProvider } from 'providers/StudySearchProvider';
import { PropsGeneSearchProvider, GeneSearchContext, emptySearch } from 'providers/GeneSearchProvider';
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'
import StudyResultsPanel from 'components/search/results/ResultsPanel'
import Study from 'components/search/results/Study'
import StudyViolinPlot from 'components/search/genes/StudyViolinPlot'
import * as ScpAPI from 'lib/scp-api'

describe('Gene search page landing', () => {
  it('shows study details when empty', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = {studies: [{name: 'foo', description: 'bar'}]}
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: false}}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <GeneSearchContext.Provider value={searchState}>
            <GeneSearchView/>
          </GeneSearchContext.Provider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))
    expect(wrapper.find(Study)).toHaveLength(1)
  })

  it('shows gene results when gene query is loaded', async () => {
    const searchState = emptySearch
    searchState.isLoaded = true
    searchState.results = {studies: [{name: 'foo', description: 'bar', gene_matches: ['agpat2']}]}
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: false}}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <GeneSearchContext.Provider  value={searchState}>
            <GeneSearchView/>
          </GeneSearchContext.Provider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))

    expect(wrapper.find(Study)).toHaveLength(0)
    const wrapperText = wrapper.find('.study-gene-result').text()
    expect(wrapperText.indexOf('This study contains agpat2 in expression data')).toBeGreaterThan(0)
  })
})
