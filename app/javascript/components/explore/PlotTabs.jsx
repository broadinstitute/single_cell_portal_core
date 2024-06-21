import React from 'react'

const tabList = [
  { key: 'loading', label: 'Loading...' },
  { key: 'scatter', label: 'Scatter' },
  { key: 'annotatedScatter', label: 'Annotated scatter' },
  { key: 'correlatedScatter', label: 'Correlation' },
  { key: 'distribution', label: 'Distribution' },
  { key: 'dotplot', label: 'Dot plot' },
  { key: 'heatmap', label: 'Heatmap' },
  { key: 'geneListHeatmap', label: 'Precomputed heatmap' },
  { key: 'spatial', label: 'Spatial' },
  { key: 'genome', label: 'Genome' },
  { key: 'infercnv-genome', label: 'Genome (inferCNV)' },
  { key: 'images', label: 'Images' }
]

const disabledTooltips = {
  'annotatedScatter': { numToSearch: '1', isMulti: false },
  'scatter': { numToSearch: '1', isMulti: false },
  'distribution': { numToSearch: '1', isMulti: false },
  'genome': { numToSearch: '1', isMulti: false },
  'correlatedScatter': { numToSearch: '2', isMulti: true },
  'dotplot': { numToSearch: '2 or more', isMulti: true },
  'heatmap': { numToSearch: '2 or more', isMulti: true }
}

/**
 * Renders tabs to navigate among plots in Explore view
 * Responsible for shows tabs available for a given view of the study
*/
export default function PlotTabs({
  shownTab, enabledTabs, disabledTabs, updateExploreParams
}) {
  return (
    <div>
      <ul
        className='nav nav-tabs study-plot-tabs'
        role="tablist"
        data-analytics-name="explore-tab"
      >
        { enabledTabs.map(tabKey => {
          const label = tabList.find(({ key }) => key === tabKey).label
          return (
            <li key={tabKey}
              role="presentation"
              aria-disabled="false"
              className={`study-nav ${tabKey === shownTab ? 'active' : ''} ${tabKey}-tab-anchor`}>
              <a onClick={() => updateExploreParams({ tab: tabKey })}>{label}</a>
            </li>
          )
        })}
        { disabledTabs.map(tabKey => {
          const label = tabList.find(({ key }) => key === tabKey).label
          const tooltip = disabledTooltips[tabKey]
          const numGenes = tooltip.numToSearch
          const geneText = `gene${tooltip.isMulti ? 's' : ''}`
          const text = `To show this plot, search ${numGenes} ${geneText} using the box at left`
          return (
            <li key={tabKey}
              role="presentation"
              aria-disabled="true"
              className={`study-nav ${tabKey}-tab-anchor disabled`}
              data-toggle="tooltip"
              data-original-title={text}
            ><a>{label}</a>
            </li>
          )
        })
        }
      </ul>
    </div>
  )
}

