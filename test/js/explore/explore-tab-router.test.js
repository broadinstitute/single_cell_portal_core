import * as Reach from '@reach/router'
import React from 'react'
import { render } from '@testing-library/react'

import useExploreTabRouter from 'components/explore/ExploreTabRouter'

/** useExploreTabRouter has useEffects, so we can't test it as a pure JS function
 * so we have this mock component which puts the return values of useExploreTabRouter
 * onto a passed-in object so they can be accessed for testing
 */
function FakeRouterComponent({ testObj }) {
  const { exploreParams, updateExploreParams } = useExploreTabRouter()
  testObj.exploreParams = exploreParams
  testObj.updateExploreParams = updateExploreParams
  return <span>Mock</span>
}

/** useExploreTabRouter reads the location.search to merge update params, so we need to mock it
  * here.  We also mock pathname since that is used in metrics-api */
function mockWindowLocationSearch(searchString) {
  delete global.window.location
  global.window = Object.create(window)
  global.window.location = {
    search: searchString,
    pathname: '/single_cell/mock'
  }
}

describe('dataParams are appropriately managed on the url', () => {
  it('provides empty cluster params from a blank url', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    routerNav.mockImplementation(() => {})
    const locationMock = jest.spyOn(Reach, 'useLocation')
    locationMock.mockImplementation(() => ({ search: '' }))

    const testObj = {}
    render(<FakeRouterComponent testObj={testObj}/>)

    expect(testObj.exploreParams.cluster).toEqual('')
    expect(testObj.exploreParams.annotation).toEqual({ name: '', type: '', scope: '' })

    testObj.updateExploreParams({ cluster: 'foo' })
    expect(routerNav).toHaveBeenLastCalledWith('?cluster=foo#study-visualize', { replace: true })
  })

  it('provides cluster params from a url with a cluster', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    routerNav.mockImplementation(() => {})
    const searchString = '?cluster=foo&annotation=bar--group--study'
    const locationMock = jest.spyOn(Reach, 'useLocation')
    locationMock.mockImplementation(() => ({ search: searchString }))
    mockWindowLocationSearch(searchString)

    const testObj = {}
    render(<FakeRouterComponent testObj={testObj}/>)

    expect(testObj.exploreParams.cluster).toEqual('foo')
    expect(testObj.exploreParams.annotation).toEqual({ name: 'bar', type: 'group', scope: 'study' })

    testObj.updateExploreParams({ annotation: { name: 'bar2', type: 'numeric', scope: 'user' } })
    expect(routerNav).toHaveBeenLastCalledWith('?cluster=foo&annotation=bar2--numeric--user#study-visualize', { replace: true })
  })

  /** This test validates that we are parsing data params on URL links in a consistent way
    * Note that if this test breaks, it may indicate that we have changed the parameter names or how
    * we are parsing them, which may break links that our users have previously created
    * So update with care */
  it('allows specifying and updating all exploreParams', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    routerNav.mockImplementation(() => {})
    const locationMock = jest.spyOn(Reach, 'useLocation')
    let urlString = '?geneList=My%20List&genes=agpat2,apoe&cluster=foo&annotation=bar--group--study&subsample=1000'
    urlString += '&spatialGroups=square,circle&consensus=mean&heatmapRowCentering=z-score&bamFileName=sample1.bam'
    urlString += '&ideogramFileId=604fc5c4e241391a8ff93271'
    locationMock.mockImplementation(() => ({ search: urlString }))
    mockWindowLocationSearch(urlString)

    const testObj = {}
    render(<FakeRouterComponent testObj={testObj}/>)

    expect(testObj.exploreParams).toEqual({
      cluster: 'foo',
      genes: ['agpat2', 'apoe'],
      geneList: 'My List',
      bamFileName: 'sample1.bam',
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      subsample: '1000',
      spatialGroups: ['square', 'circle'],
      isSplitLabelArrays: null,
      consensus: 'mean',
      heatmapRowCentering: 'z-score',
      ideogramFileId: '604fc5c4e241391a8ff93271',
      distributionPlot: '',
      distributionPoints: '',
      heatmapFit: '',
      scatterColor: '',
      tab: '',
      expressionFilter: [0, 1],
      hiddenTraces: [],
      userSpecified: {
        annotation: true,
        bamFileName: true,
        cluster: true,
        consensus: true,
        genes: true,
        geneList: true,
        spatialGroups: true,
        subsample: true,
        heatmapRowCentering: true,
        ideogramFileId: true
      }
    })
    testObj.updateExploreParams({ spatialGroups: ['triangle'] })
    let expectedUrlString = '?geneList=My%20List&genes=agpat2%2Capoe&cluster=foo&spatialGroups=triangle&annotation=bar--group--study&subsample=1000'
    expectedUrlString += '&consensus=mean&heatmapRowCentering=z-score&bamFileName=sample1.bam&ideogramFileId=604fc5c4e241391a8ff93271#study-visualize'
    expect(routerNav).toHaveBeenLastCalledWith(expectedUrlString, { replace: true })
  })
})
