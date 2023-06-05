import React from 'react'

const disabledTooltips = {
  'annotatedScatter': { numToSearch: '1', isMulti: false },
  'scatter': { numToSearch: '1', isMulti: false },
  'distribution': { numToSearch: '1', isMulti: false },
  'correlatedScatter': { numToSearch: '2', isMulti: true },
  'dotplot': { numToSearch: '2 or more', isMulti: true },
  'heatmap': { numToSearch: '2 or more', isMulti: true }
}

/**
 * Renders tabs to navigate among plots in Explore view
 * Responsible for shows tabs available for a given view of the study
*/
export default function PlotTabs({
  shownTab, enabledTabs, disabledTabs, tabList, updateExploreParams,
  isNewExploreUX
}) {
  return (
    <div className={isNewExploreUX ? '' : 'col-md-4 col-md-offset-1'}>
      <ul
        className={isNewExploreUX ? 'nav nav-tabs study-plot-tabs' : 'nav nav-tabs'}
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
        {isNewExploreUX &&
          disabledTabs.map(tabKey => {
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

