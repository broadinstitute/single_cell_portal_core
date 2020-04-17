import React from 'react';
import * as ReactAll from 'react';
import { mount } from 'enzyme';
import * as Reach from '@reach/router'

const fetch = require('node-fetch');

import GeneSearchView from 'components/search/genes/GeneSearchView';
import GeneResultsPanel from 'components/search/genes/GeneResultsPanel';
import SearchPanel from 'components/search/controls/SearchPanel';
import { PropsStudySearchProvider } from 'providers/StudySearchProvider';
import { PropsGeneSearchProvider, GeneSearchContext, emptySearch } from 'providers/GeneSearchProvider';
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'
import StudyResultsPanel from 'components/search/results/ResultsPanel'
import * as ScpAPI from 'lib/scp-api'

describe('Gene search page landing', () => {
  it('shows studies when empty', async () => {
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: false}}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <GeneSearchContext.Provider value={emptySearch}>
            <GeneSearchView/>
          </GeneSearchContext.Provider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))
    expect(wrapper.find(StudyResultsPanel)).toHaveLength(1)
  })
  it('shows gene results when gene query is loaded', async () => {
    const activeSearchState = emptySearch
    activeSearchState.isLoaded = true
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: false}}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <GeneSearchContext.Provider  value={activeSearchState}>
            <GeneSearchView/>
          </GeneSearchContext.Provider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))
    expect(wrapper.find(GeneResultsPanel)).toHaveLength(1)
  })
})

describe('Gene search page study filter', () => {
  it('does not show or apply study filter when feature flag is off', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: false}}>
        <PropsStudySearchProvider searchParams={{terms: 'foobar', facets:{}, page: 1}}>
          <PropsGeneSearchProvider searchParams={{genes: '', page: 1}}>
            <GeneSearchView/>
          </PropsGeneSearchProvider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))
    expect(wrapper.find('.gene-study-filter')).toHaveLength(0)
    expect(wrapper.find(SearchPanel)).toHaveLength(0)
    wrapper.find('input[name="genesText"]').simulate('change', {target: { value: 'test345'}});
    wrapper.find('input[name="genesText"]').simulate('submit')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&genes=test345&genePage=1')
  })
  it('shows and applies study filter when feature flag is on', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    const wrapper = mount((
      <FeatureFlagContext.Provider value={{gene_study_filter: true}}>
        <PropsStudySearchProvider searchParams={{terms: 'foobar2', facets:{}, page: 1}}>
          <PropsGeneSearchProvider searchParams={{genes: '', page: 1}}>
            <GeneSearchView/>
          </PropsGeneSearchProvider>
        </PropsStudySearchProvider>
      </FeatureFlagContext.Provider>
    ))
    expect(wrapper.find('.gene-study-filter')).toHaveLength(1)
    expect(wrapper.find(SearchPanel)).toHaveLength(1)
    wrapper.find('input[name="genesText"]').simulate('change', {target: { value: 'test567'}});
    wrapper.find('input[name="genesText"]').simulate('submit')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&terms=foobar2&genes=test567&genePage=1')
  })
})



