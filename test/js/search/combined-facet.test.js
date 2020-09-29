import React from 'react';
import * as ReactAll from 'react';
import { mount } from 'enzyme';
import * as Reach from '@reach/router'

const fetch = require('node-fetch');

import CombinedFacetControl from 'components/search/controls/CombinedFacetControl';
import { PropsStudySearchProvider } from 'providers/StudySearchProvider';
import { SearchFacetContext } from 'providers/SearchFacetProvider';
import * as ScpAPI from 'lib/scp-api'

const organFacet = {
    name: "Organ",
    id: "organ",
    type: "string",
    links: [{name: "NCBI Taxonomy", url: "https://foo.tdb"}],
    filters: [
      {id: 'organId1', name: 'name 1'},
      {id: 'organId2', name: 'name 2'},
      {id: 'organId3', name: 'name 3'},
      {id: 'organId4', name: 'name 4'},
      {id: 'organId5', name: 'name 5'},
      {id: 'organId6', name: 'name 6'}
    ],
    links: []
  }

const organRegionFacet = {
  name: "Organ",
  id: "organ_region",
  type: "string",
  links: [{name: "NCBI Taxonomy", url: "https://foo.tdb"}],
  filters: [
    {id: 'organRegionId1', name: 'name 1'},
    {id: 'organRegionId2', name: 'name 2'},
    {id: 'organRegionId3', name: 'name 3'},
    {id: 'organRegionId4', name: 'name 4'},
    {id: 'organRegionId5', name: 'name 5'},
    {id: 'organRegionId6', name: 'name 6'}
  ],
  links: []
}

describe('facets work within the multi-facet container', () => {
  it('handles multiple checkbox selections in a single facet', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')

    const facetContext = {
      facets: [organFacet, organRegionFacet],
      isLoading: false,
      isLoaded: false
    }
    let organControl = function() {
      return wrapper.find('#filters-box-searchable-organ').first()
    }
    let applyButton = function() {
      return wrapper.find('button.facet-apply-button')
    }

    const wrapper = mount((
      <SearchFacetContext.Provider value={facetContext}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <CombinedFacetControl facetIds={['organ', 'organ_region']} controlName="organC"/>
        </PropsStudySearchProvider>
      </SearchFacetContext.Provider>
    ))

    expect(wrapper.find('.facet')).toHaveLength(1)
    expect(wrapper.find('.facet').hasClass('active')).toEqual(false)
    expect(wrapper.find('.multi-facet-container')).toHaveLength(0)

    wrapper.find('.facet > a').first().simulate('click')
    expect(wrapper.find('.facet').hasClass('active')).toEqual(true)
    expect(applyButton().hasClass('active')).toEqual(false)
    expect(wrapper.find('.multi-facet-container')).toHaveLength(1)
    expect(applyButton()).toHaveLength(1)
    expect(organControl().find('.facet-filter-list li').length).toEqual(organFacet.filters.length)

    // after clicking, apply is enabled, and a badge for the selection is shown
    organControl().find('input#organId5').simulate('change', {target: {checked: true}})
    expect(applyButton().hasClass('active')).toEqual(true)
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(1)
    expect(organControl().find('.filter-badge-list .badge').text().trim()).toEqual('name 5')

    // after unselect, apply is disabled, and a badge for the selection is removed
    organControl().find('input#organId5').simulate('change', {target: {checked: false}})
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(0)

    // after two selections, two badges are shown
    organControl().find('input#organId3').simulate('change', {target: {checked: true}})
    organControl().find('input#organId6').simulate('change', {target: {checked: true}})
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(2)

    // apply sends a routing request to the right url
    applyButton().simulate('click')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&facets=organ%3AorganId3%2CorganId6')
  })

  it('handles multiple checkbox selections across two facets', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')

    const facetContext = {
      facets: [organFacet, organRegionFacet],
      isLoading: false,
      isLoaded: false
    }
    let organControl = function() {
      return wrapper.find('#filters-box-searchable-organ').first()
    }
    let organRegionControl = function() {
      return wrapper.find('#filters-box-searchable-organ_region').first()
    }
    let applyButton = function() {
      return wrapper.find('button.facet-apply-button')
    }
    let clearButton = function() {
      return wrapper.find('span.clear-filters')
    }

    const wrapper = mount((
      <SearchFacetContext.Provider value={facetContext}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <CombinedFacetControl facetIds={['organ', 'organ_region']} controlName="organC"/>
        </PropsStudySearchProvider>
      </SearchFacetContext.Provider>
    ))

    wrapper.find('.facet > a').first().simulate('click')

    // after clicking, apply is enabled, and a badge for the selection is shown
    organControl().find('input#organId5').simulate('change', {target: {checked: true}})
    organRegionControl().find('input#organRegionId1').simulate('change', {target: {checked: true}})
    organRegionControl().find('input#organRegionId3').simulate('change', {target: {checked: true}})
    expect(applyButton().hasClass('active')).toEqual(true)
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(1)
    expect(organRegionControl().find('.filter-badge-list .badge').length).toEqual(2)

    // after clear, both facets are cleared
    clearButton().simulate('click')
    expect(applyButton().hasClass('active')).toEqual(false)
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(0)
    expect(organRegionControl().find('.filter-badge-list .badge').length).toEqual(0)

    // after more selections, apply sends a routing request to the right url
    organControl().find('input#organId6').simulate('change', {target: {checked: true}})
    organRegionControl().find('input#organRegionId2').simulate('change', {target: {checked: true}})
    organRegionControl().find('input#organRegionId4').simulate('change', {target: {checked: true}})
    applyButton().simulate('click')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&facets=organ%3AorganId6%2Borgan_region%3AorganRegionId2%2CorganRegionId4')
  })

  it('handles where one facet of the combination is not populated in the environment', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')

    const facetContext = {
      facets: [organFacet],
      isLoading: false,
      isLoaded: false
    }
    let organControl = function() {
      return wrapper.find('#filters-box-searchable-organ').first()
    }
    let applyButton = function() {
      return wrapper.find('button.facet-apply-button')
    }
    let clearButton = function() {
      return wrapper.find('span.clear-filters')
    }

    const wrapper = mount((
      <SearchFacetContext.Provider value={facetContext}>
        <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
          <CombinedFacetControl facetIds={['organ', 'organ_region']} controlName="organC"/>
        </PropsStudySearchProvider>
      </SearchFacetContext.Provider>
    ))

    wrapper.find('.facet > a').first().simulate('click')

    // after clicking, apply is enabled, and a badge for the selection is shown
    expect(wrapper.find('#filters-box-searchable-organ')).toHaveLength(1)
    expect(wrapper.find('#filters-box-searchable-organ_region')).toHaveLength(0)
    organControl().find('input#organId5').simulate('change', {target: {checked: true}})
    expect(applyButton().hasClass('active')).toEqual(true)
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(1)

    // clear still works
    clearButton().simulate('click')
    expect(applyButton().hasClass('active')).toEqual(false)
    expect(organControl().find('.filter-badge-list .badge').length).toEqual(0)

    // apply still works
    organControl().find('input#organId6').simulate('change', {target: {checked: true}})
    applyButton().simulate('click')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&facets=organ%3AorganId6')
  })
})

