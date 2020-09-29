import React from 'react';
import * as ReactAll from 'react';
import { mount } from 'enzyme';
import * as Reach from '@reach/router'

const fetch = require('node-fetch');

import FacetControl from 'components/search/controls/FacetControl';
import { PropsStudySearchProvider } from 'providers/StudySearchProvider';
import * as ScpAPI from 'lib/scp-api'

const speciesFacet = {
    name: "Species",
    id: "species",
    type: "string",
    links: [{name: "NCBI Taxonomy", url: "https://foo.tdb"}],
    filters: [
      {id: 'speciesId1', name: 'name 1'},
      {id: 'speciesId2', name: 'name 2'},
      {id: 'speciesId3', name: 'name 3'},
      {id: 'speciesId4', name: 'name 4'},
      {id: 'speciesId5', name: 'name 5'},
      {id: 'speciesId6', name: 'name 6'}
    ],
    links: []
  }

describe('Facet control handles selections appropriately', () => {
  it('handles multiple checkbox selections', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')

    let speciesControl = function() {
      return wrapper.find('#facet-species').first()
    }
    const wrapper = mount((
      <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
        <FacetControl facet={speciesFacet}/>
      </PropsStudySearchProvider>
    ))

    expect(speciesControl()).toHaveLength(1)
    expect(speciesControl().hasClass('active')).toEqual(false)
    wrapper.find('#facet-species > a').simulate('click')
    expect(speciesControl().hasClass('active')).toEqual(true)

    expect(speciesControl().find('.facet-filter-list li').length).toEqual(speciesFacet.filters.length)

    // after clicking, apply is enabled, and a badge for the selection is shown
    speciesControl().find('input#speciesId5').simulate('change', {target: {checked: true}})
    expect(speciesControl().find('button.facet-apply-button').hasClass('active')).toEqual(true)
    expect(speciesControl().find('.filter-badge-list .badge').length).toEqual(1)
    expect(speciesControl().find('.filter-badge-list .badge').text().trim()).toEqual('name 5')

    // after unselect, apply is disabled, and a badge for the selection is removed
    speciesControl().find('input#speciesId5').simulate('change', {target: {checked: false}})
    expect(speciesControl().find('.filter-badge-list .badge').length).toEqual(0)

    // after two selections, two badges are shown
    speciesControl().find('input#speciesId3').simulate('change', {target: {checked: true}})
    speciesControl().find('input#speciesId6').simulate('change', {target: {checked: true}})
    expect(speciesControl().find('.filter-badge-list .badge').length).toEqual(2)

    // apply sends a routing request to the right url
    speciesControl().find('button.facet-apply-button').simulate('click')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&facets=species%3AspeciesId3%2CspeciesId6')
  })
})

const longSpeciesFacet = {
    name: "Species",
    id: "species",
    type: "string",
    links: [{name: "NCBI Taxonomy", url: "https://foo.tdb"}],
    filters: [
      {id: 'speciesId1', name: 'name 1'},
      {id: 'speciesId2', name: 'name 2'},
      {id: 'speciesId3', name: 'name 3'},
      {id: 'speciesId4', name: 'name 4'},
      {id: 'speciesId5', name: 'name 5'},
      {id: 'speciesId6', name: 'name 6'},
      {id: 'speciesId7', name: 'name 7'},
      {id: 'speciesId8', name: 'name 8'},
      {id: 'speciesId9', name: 'name 9'},
      {id: 'speciesId10', name: 'name 10'},
      {id: 'speciesId11', name: 'name 11'},
      {id: 'speciesId12', name: 'name 12'},
      {id: 'speciesId13', name: 'name 13'},
      {id: 'speciesId14', name: 'name 14'},
      {id: 'speciesId15', name: 'name 15'},
      {id: 'speciesId16', name: 'name 16'},
      {id: 'speciesId17', name: 'name 17'},
      {id: 'speciesId18', name: 'name 18'},
      {id: 'speciesId19', name: 'name 19'},
      {id: 'speciesId20', name: 'name 20'},
      {id: 'speciesId21', name: 'name 21'},
      {id: 'speciesId22', name: 'name 22'}
    ],
    links: []
  }

describe('Facet control handles facets with many filters', () => {
  it('truncates the list when appropriate', async () => {

    const routerNav = jest.spyOn(Reach, 'navigate')

    let speciesControl = function() {
      return wrapper.find('#facet-species').first()
    }
    const wrapper = mount((
      <PropsStudySearchProvider searchParams={{terms: '', facets:{}, page: 1}}>
        <FacetControl facet={longSpeciesFacet}/>
      </PropsStudySearchProvider>
    ))

    wrapper.find('#facet-species > a').simulate('click')
    // by default, only show the first 15 filters
    expect(speciesControl().find('.facet-filter-list li').length).toEqual(22)

    speciesControl().find('input#speciesId2').simulate('change', {target: {checked: true}})
    expect(speciesControl().find('button.facet-apply-button').hasClass('active')).toEqual(true)

    speciesControl().find('button.facet-apply-button').simulate('click')
    expect(routerNav).toHaveBeenLastCalledWith('?type=study&page=1&facets=species%3AspeciesId2')
  })
})
