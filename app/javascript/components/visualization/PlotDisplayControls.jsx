import React from 'react'
import Panel from 'react-bootstrap/lib/Panel'
import { Slider, Rail, Handles, Tracks, Ticks } from 'react-compound-slider'

import Select from '~/lib/InstrumentedSelect'
import { Handle, Track, Tick } from '~/components/search/controls/slider/components'
import PlotOptions from './plot-options'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faExternalLinkSquareAlt, faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'
const {
  SCATTER_COLOR_OPTIONS, defaultScatterColor, DISTRIBUTION_PLOT_OPTIONS, DISTRIBUTION_POINTS_OPTIONS,
  ROW_CENTERING_OPTIONS, FIT_OPTIONS
} = PlotOptions

const sliderStyle = {
  margin: '5%',
  position: 'relative',
  width: '90%'
}

const railStyle = {
  position: 'absolute',
  width: '100%',
  height: 14,
  borderRadius: 7,
  cursor: 'pointer',
  backgroundColor: 'rgb(155,155,155)'
}
// disabled because the feature is not yet finalized from a product/UX standpoint, but
// the code is in because it allows easier testing of the trace filtering logic implemented in plot.js
const ENABLE_EXPRESSION_FILTER = false

export const EXPRESSION_SORT_OPTIONS = ['high', 'low', 'unsorted']
/** the graph customization controls for the exlore tab */
export default function RenderControls({ shownTab, exploreParams, updateExploreParams, expressionSort, allGenes }) {
  const scatterColorValue = exploreParams.scatterColor ? exploreParams.scatterColor : defaultScatterColor
  let distributionPlotValue = DISTRIBUTION_PLOT_OPTIONS.find(opt => opt.value === exploreParams.distributionPlot)
  if (!distributionPlotValue) {
    distributionPlotValue = DISTRIBUTION_PLOT_OPTIONS[0]
  }
  let heatmapRowCenteringValue = ROW_CENTERING_OPTIONS.find(opt => opt.value === exploreParams.heatmapRowCentering)
  if (!heatmapRowCenteringValue) {
    heatmapRowCenteringValue = ROW_CENTERING_OPTIONS[0]
  }
  let heatmapFitValue = FIT_OPTIONS.find(opt => opt.value === exploreParams.heatmapFit)
  if (!heatmapFitValue) {
    heatmapFitValue = FIT_OPTIONS[0]
  }

  let distributionPointsValue = DISTRIBUTION_POINTS_OPTIONS.find(opt => opt.value === exploreParams.distributionPoints)
  if (!distributionPointsValue) {
    distributionPointsValue = DISTRIBUTION_POINTS_OPTIONS[0]
  }

  const showScatter = (
    shownTab === 'scatter' &&
    (exploreParams.annotation.type === 'numeric' || exploreParams.genes.length)
  )
  const showColorScale = !!(showScatter && (exploreParams.annotation.type === 'numeric' || exploreParams.genes.length))
  const filterValues = exploreParams.expressionFilter ?? [0, 1]
  const showExpressionFilter = ENABLE_EXPRESSION_FILTER && exploreParams.genes.length && showScatter
  const showExpressionSort = exploreParams.genes.length > 0 && showScatter

  const expressionSortPopover = <Popover id={`expression-sort-popover`}>
    Specify which cells to bring to the front of expression-based scatter plots based on expression value.&nbsp;
    <a href="https://singlecell.zendesk.com/hc/en-us/articles/31772258040475" target="_blank">Learn more</a>.
  </Popover>
  const sortDocumentationLink =
    <OverlayTrigger trigger={['hover', 'focus']} rootClose placement="left" overlay={expressionSortPopover} delayHide={1500}>
        <a className="action help-icon"><FontAwesomeIcon icon={faInfoCircle}/></a>
    </OverlayTrigger>

  return (
    <div>
      { showColorScale && <div className="render-controls">
        <label className="labeled-select">Continuous color scale
          <span className="detail"> (for numeric data)</span>
          <Select
            data-analytics-name="scatter-color-picker"
            options={SCATTER_COLOR_OPTIONS.map(opt => ({
              label: opt,
              value: opt
            }))}
            value={{
              label: scatterColorValue,
              value: scatterColorValue
            }}
            clearable={false}
            onChange={option => updateExploreParams({ scatterColor: option.value })}/>
        </label>
      </div>}
      {showExpressionSort && <div className="render-controls">
        <label className="labeled-select">Order expression by&nbsp;
          {sortDocumentationLink}
          <Select
            data-analytics-name="expression-sort-select"
            options={EXPRESSION_SORT_OPTIONS.map(opt => ({
              label: opt,
              value: opt
            }))}
            value={{
              label: expressionSort,
              value: expressionSort
            }}
            clearable={false}
            onChange={option => updateExploreParams({ expressionSort: option.value })}/>
        </label>
      </div>}
      {showExpressionFilter && <div className="render-controls">
        <label>Expression filter</label>
        <Slider
          mode={1}
          step={0.05}
          domain={[0, 1.0]}
          rootStyle={sliderStyle}
          values={filterValues}
          onChange={newValues => {
            updateExploreParams({ expressionFilter: newValues })
          }}
        >
          <Rail>
            {({ getRailProps }) => (
              <div style={railStyle} {...getRailProps()} />
            )}
          </Rail>
          <Handles>
            {({ handles, getHandleProps }) => (
              <div className='slider-handles'>
                {handles.map(handle => (
                  <Handle
                    key={handle.id}
                    handle={handle}
                    domain={[0, 1]}
                    getHandleProps={getHandleProps}
                  />
                ))}
              </div>
            )}
          </Handles>
          <Tracks left={false} right={false}>
            {({ tracks, getTrackProps }) => (
              <div className='slider-tracks'>
                {tracks.map(({ id, source, target }) => (
                  <Track
                    key={id}
                    source={source}
                    target={target}
                    getTrackProps={getTrackProps}
                  />
                ))}
              </div>
            )}
          </Tracks>
          <Ticks values={[0, 1]}>
            {({ ticks }) => (
              <div className='slider-ticks'>
                {ticks.map(tick => (
                  <Tick key={tick.id} tick={tick} count={ticks.length}
                    format={val => val == 0 ? 'min' : 'max'}
                  />
                ))}
              </div>
            )}
          </Ticks>
        </Slider>
        <br/><br/><br/>
      </div> }
      <Panel className={shownTab === 'distribution' ? '' : 'hidden'}>
        <Panel.Heading>
          <Panel.Title>
            Distribution
          </Panel.Title>
        </Panel.Heading>
        <Panel.Body>
          <label className="labeled-select">Plot type
            <Select data-analytics-name="distribution-plot-picker"
              options={DISTRIBUTION_PLOT_OPTIONS}
              value={distributionPlotValue}
              clearable={false}
              isSearchable={false}
              onChange={option => updateExploreParams({
                distributionPlot: option.value,
                distributionPoints: distributionPointsValue.value
              })}/>
          </label>
          <label className="labeled-select">Data points
            <Select data-analytics-name="distribution-points-picker"
              options={DISTRIBUTION_POINTS_OPTIONS}
              value={distributionPointsValue}
              clearable={false}
              isSearchable={false}
              onChange={option => updateExploreParams({
                distributionPlot: distributionPlotValue.value,
                distributionPoints: option.value
              })}/>
          </label>
        </Panel.Body>
      </Panel>
      <Panel className={['heatmap', 'geneListHeatmap'].includes(shownTab) ? '' : 'hidden'}>
        <Panel.Heading>
          <Panel.Title>
            Heatmap
          </Panel.Title>
        </Panel.Heading>
        <Panel.Body>
          <label className="labeled-select">Row centering
            <Select data-analytics-name="row-centering-picker"
              options={ROW_CENTERING_OPTIONS}
              value={heatmapRowCenteringValue}
              clearable={false}
              isSearchable={false}
              onChange={option => updateExploreParams({ heatmapRowCentering: option.value })}/>
          </label>
          <label className="labeled-select">Fit options
            <Select data-analytics-name="fit-picker"
              options={FIT_OPTIONS}
              value={heatmapFitValue}
              clearable={false}
              isSearchable={false}
              onChange={option => updateExploreParams({ heatmapFit: option.value })}/>
          </label>
        </Panel.Body>
      </Panel>
    </div>
  )
}
