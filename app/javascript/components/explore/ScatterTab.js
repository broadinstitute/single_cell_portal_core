import React, { useState, useEffect, useRef } from 'react'

import ScatterPlot from 'components/visualization/ScatterPlot'
import { newCache } from './plotDataCache'
// we allow 8 plotly contexts -- each plotly graph consumes 3 webgl contexts,
// and chrome by defualt allows up to 32 simultaneous webgl contexts
// so 8 plotly graphs will consume 24 contexts, leaving 8 more, for, e.g., a
// distribution graph
const PLOTLY_CONTEXT_NAMES = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']
const MAX_PLOTS = PLOTLY_CONTEXT_NAMES.length
/**
  * renders the scatter tab.
  */
export default function ScatterTab({
  exploreInfo, exploreParams, updateExploreParams, studyAccession, isGene, isMultiGene,
  plotPointsSelected, isCellSelecting, getPlotDimensions
}) {
  // maintain the map of plotly contexts to the params that generated the corresponding visualization
  const plotlyContextMap = useRef({})
  const [dataCache] = useState(newCache())
  const { scatterParams, isTwoColumn, isMultiRow, firstRowSingleCol } = getScatterParams(
    exploreInfo, exploreParams, isGene, isMultiGene
  )

  /** helper function for Scatter plot color updates */
  function updateScatterColor(color) {
    updateExploreParams({ scatterColor: color }, false)
  }

  // identify any repeat graphs
  const newContextMap = getNewContextMap(scatterParams, plotlyContextMap.current)

  useEffect(() => {
    plotlyContextMap.current = newContextMap
  }, [])

  return <div className="row">
    { scatterParams.map((params, index) => {
      const isTwoColRow = isTwoColumn && !(index === 0 && firstRowSingleCol)
      const key = getKeyFromScatterParams(params)

      return <div className={isTwoColRow ? 'col-md-6' : 'col-md-12'} key={newContextMap[key]}>
        <ScatterPlot
          {...{
            studyAccession, plotPointsSelected, isCellSelecting, updateScatterColor
          }}
          {...params}
          dataCache={dataCache}
          dimensions={getPlotDimensions({
            isMultiRow,
            isTwoColumn: isTwoColRow,
            hasTitle: true
          })}
        />
      </div>
    })}
    { scatterParams.length > MAX_PLOTS &&
      <div className="panel">
        <span>Due to browser limitations, only 8 plots can be shown at one time.  Deselect some spatial groups</span>
      </div>
    }
  </div>
}

/** returns an array of params objects suitable for passing into ScatterPlot components
 * (one for each plot).  Also returns layout variables
 * This handles 6 permutations: (spatial / noSpatial) X (no / single / multigene)
 * note that we always pass and/or manipulate copies of the explore params for safety reasons, as we
 * never want to directly modify the exploreParams object
 */
export function getScatterParams(exploreInfo, exploreParams, isGene, isMultiGene) {
  let isTwoColumn = true
  let isMultiRow = false
  let firstRowSingleCol = false
  const isSpatial = exploreParams.spatialGroups?.length > 0

  const scatterParams = []
  if (isMultiGene && !exploreParams.consensus) {
    if (isSpatial) {
      // for multi-gene spatial, show the reference spatial cluster at the top, then
      // show the expression in the spatial files
      // we don't support multi-gene multi-spatial, so only the first spatial group is shown
      firstRowSingleCol = true
      isMultiRow = true
      // first plot is reference cluster, so no genes
      scatterParams.push({ ...exploreParams, cluster: exploreParams.spatialGroups[0], genes: [] })
      exploreParams.genes.forEach(gene => {
        scatterParams.push({ ...exploreParams, cluster: exploreParams.spatialGroups[0], genes: [gene] })
      })
    } else {
      // for non-spatial multigene, show each gene, with the cluster as the second plot
      isMultiRow = true
      exploreParams.genes.forEach((gene, index) => {
        scatterParams.push({ ...exploreParams, genes: [exploreParams.genes[index]] })
        if (index === 0) {
          scatterParams.push({ ...exploreParams, genes: [] })
        }
      })
    }
  } else if (isGene) {
    if (isSpatial) {
      // for single-gene spatial, show the gene expression and reference cluster, then the expression
      // overlaid over the spatial plot, then the spatial-cluster plot
      scatterParams.push({ ...exploreParams })
      scatterParams.push({ ...exploreParams, genes: [] })
      // show a row for each spatial group selected
      exploreParams.spatialGroups.forEach(spatialGroup => {
        scatterParams.push({ ...exploreParams, cluster: spatialGroup })
        scatterParams.push({ ...exploreParams, cluster: spatialGroup, genes: [] })
      })
    } else {
      // for single-gene non-spatial, show the expression plot and the cluster plot
      // for the expression plot, use the params as-is (but pass a copy for safety reasons)
      scatterParams.push({ ...exploreParams })
      // for the cluster plot, we want the same params, but with no genes.
      scatterParams.push({ ...exploreParams, genes: [] })
    }
  } else {
    // no gene search, just showing clusters
    if (isSpatial) {
      // for spatial non-gene, show the cluster, and then a plot for each spatial cluster
      scatterParams.push({ ...exploreParams })
      exploreParams.spatialGroups.forEach(spatialGroup => {
        scatterParams.push({ ...exploreParams, cluster: spatialGroup })
      })
    } else {
      isTwoColumn = false
      // for non-spatial non-gene, just show the cluster
      scatterParams.push({ ...exploreParams })
    }
  }
  return { scatterParams: scatterParams.slice(0, MAX_PLOTS), isTwoColumn, isMultiRow, firstRowSingleCol, isSpatial }
}


/** returns a map of key => plotlycontext.  If a scatterParams corresponds to an
  * already-rendered plot, it will be mapped to that existing context.  Otherwise,
  * it will be assigned an unused context.
  *. This lets us recycle plotly (and thus webgl) contexts effectively, while
  * avoiding re-drawing plots that are already rendered
   */
export function getNewContextMap(scatterParams, oldContextMap) {
  // find out which contexts correspond to graphs we will be rendering again
  const repeatContexts = scatterParams.map(params => {
    const key = getKeyFromScatterParams(params)
    return oldContextMap[key]
  })
  // get the unused contexts, so we know which ones can be reassigned
  const unusedContexts = PLOTLY_CONTEXT_NAMES.filter(c => !repeatContexts.includes(c))
  const newContextMap = {}
  // now for each params, assign it to its already-existing context, or grab an unused one
  scatterParams.forEach(params => {
    const key = getKeyFromScatterParams(params)
    let plotlyContext = oldContextMap[key]
    if (!plotlyContext) {
      plotlyContext = unusedContexts.shift()
    }
    newContextMap[key] = plotlyContext
  })
  return newContextMap
}

/** returns a string from a params object, that uniquely identifies what was plotted */
function getKeyFromScatterParams(params) {
  return params.cluster + params.genes.join('-') + params.annotation.name
}
