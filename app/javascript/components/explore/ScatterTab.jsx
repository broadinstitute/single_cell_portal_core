import React, { useEffect, useRef, useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faImage } from '@fortawesome/free-solid-svg-icons'

import ScatterPlot from '~/components/visualization/ScatterPlot'
import BucketImage from '~/components/visualization/BucketImage'

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
  exploreInfo, exploreParamsWithDefaults, updateExploreParamsWithDefaults, studyAccession, isGene, isMultiGene,
  plotPointsSelected, isCellSelecting, showRelatedGenesIdeogram, showViewOptionsControls, showDifferentialExpressionTable,
  scatterColor, countsByLabel, setCountsByLabel, dataCache
}) {
  // maintain the map of plotly contexts to the params that generated the corresponding visualization
  const plotlyContextMap = useRef({})
  const { scatterParams, isTwoColumn, isMultiRow, firstRowSingleCol } =
    getScatterParams(exploreParamsWithDefaults, isGene, isMultiGene)

  const imagesForClusters = {}
  exploreInfo.imageFiles.map(file => {
    file.associated_clusters.map(clusterName => {
      imagesForClusters[clusterName] = imagesForClusters[clusterName] ? imagesForClusters[clusterName] : []
      imagesForClusters[clusterName].push(file)
    })
  })

  /** helper function for Scatter plot color updates */
  function updateScatterColor(color) {
    updateExploreParamsWithDefaults({ scatterColor: color }, false)
  }

  // identify any repeat graphs
  const newContextMap = getNewContextMap(scatterParams, plotlyContextMap.current)

  useEffect(() => {
    plotlyContextMap.current = newContextMap
  }, [])

  return <div className="row">
    {
      scatterParams.map((params, index) => {
        let associatedImages = []
        if (imagesForClusters[params.cluster] && params.genes.length === 0) {
          // only show the reference image under the cluster plot, not the expression plot
          associatedImages = imagesForClusters[params.cluster]
        }
        const isTwoColRow = isTwoColumn && !(index === 0 && firstRowSingleCol)
        const key = getKeyFromScatterParams(params)
        let rowDivider = <span key={`d${index}`}></span>
        if (index % 2 === 1 && !isMultiGene) {
          // Use a full-width empty column to make sure plots align into rows, even if they are unequal height
          rowDivider = <div className="col-md-12" key={`d${index}`}></div>
        }
        return [
          <div className={isTwoColRow ? 'col-md-6' : 'col-md-12'} key={key}>
            <ScatterPlot
              {...{
                studyAccession, plotPointsSelected, isCellSelecting, updateScatterColor,
                countsByLabel, setCountsByLabel, updateExploreParams: updateExploreParamsWithDefaults
              }}
              {...params}
              dataCache={dataCache}
              scatterColor={scatterColor}
              canEdit={exploreInfo.canEdit}
              bucketId={exploreInfo.bucketId}
              dimensionProps={{
                isMultiRow,
                isTwoColumn: isTwoColRow,
                showRelatedGenesIdeogram, showViewOptionsControls,
                showDifferentialExpressionTable
              }}
            />
            { associatedImages.map(imageFile => <ImageDisplay
              key={imageFile.name}
              file={imageFile}
              bucketName={exploreInfo.bucketId}/>) }
          </div>,
          rowDivider
        ]
      /* equivalent to .flat(), but .flat() isn't supported in travis node yet */
      }).reduce((acc, val) => acc.concat(val), [])
    }
    { scatterParams.length > MAX_PLOTS &&
      <div className="panel">
        <span>Due to browser limitations, only 8 plots can be shown at one time.  Deselect some spatial groups</span>
      </div>
    }
  </div>
}


/** Renders a given image with name and description and show/hide controls */
function ImageDisplay({ file, bucketName }) {
  const [show, setShow] = useState(true)
  return <div>
    <h5 className="plot-title">
      <FontAwesomeIcon icon={faImage} className="fa-lg fas"/> {file.name}
      &nbsp;
      <button aria-label="Toggle show image" className="action" onClick={() => setShow(!show)}>[{show ? 'hide' : 'show'}]</button>
    </h5>
    { show &&
      <div>
        <BucketImage fileName={file.bucket_file_name} bucketName={bucketName}/>
        <p className="help-block">
          { file.description &&
            <span>{file.description}</span>
          }
        </p>
      </div>
    }
  </div>
}


/** returns an array of params objects suitable for passing into ScatterPlot components
 * (one for each plot).  Also returns layout variables
 * This handles 6 permutations: (spatial / noSpatial) X (no / single / multigene)
 * note that we always pass and/or manipulate copies of the explore params for safety reasons, as we
 * never want to directly modify the exploreParamsWithDefaults object
 */
export function getScatterParams(exploreParamsWithDefaults, isGene, isMultiGene) {
  let isTwoColumn = true
  let isMultiRow = false
  let firstRowSingleCol = false
  const isSpatial = exploreParamsWithDefaults?.spatialGroups?.length > 0

  const scatterParams = []
  if (isMultiGene && !exploreParamsWithDefaults.consensus) {
    if (isSpatial) {
      // for multi-gene spatial, show the reference spatial cluster at the top, then
      // show the expression in the spatial files
      // we don't support multi-gene multi-spatial, so only the first spatial group is shown
      firstRowSingleCol = true
      isMultiRow = true
      // first plot is reference cluster, so no genes
      scatterParams.push({ ...exploreParamsWithDefaults, cluster: exploreParamsWithDefaults.spatialGroups[0], genes: [] })
      exploreParamsWithDefaults.genes.forEach(gene => {
        scatterParams.push({ ...exploreParamsWithDefaults, cluster: exploreParamsWithDefaults.spatialGroups[0], genes: [gene] })
      })
    } else {
      // for non-spatial multigene, show each gene, with the cluster as the second plot
      isMultiRow = true
      exploreParamsWithDefaults.genes.forEach((gene, index) => {
        scatterParams.push({ ...exploreParamsWithDefaults, genes: [exploreParamsWithDefaults.genes[index]] })
        if (index === 0) {
          scatterParams.push({ ...exploreParamsWithDefaults, genes: [] })
        }
      })
    }
  } else if (isGene) {
    if (isSpatial) {
      // for single-gene spatial, show the gene expression and reference cluster, then the expression
      // overlaid over the spatial plot, then the spatial-cluster plot
      scatterParams.push({ ...exploreParamsWithDefaults })
      scatterParams.push({ ...exploreParamsWithDefaults, genes: [] })
      // show a row for each spatial group selected
      exploreParamsWithDefaults.spatialGroups.forEach(spatialGroup => {
        scatterParams.push({ ...exploreParamsWithDefaults, cluster: spatialGroup })
        scatterParams.push({ ...exploreParamsWithDefaults, cluster: spatialGroup, genes: [] })
      })
    } else {
      // for single-gene non-spatial, show the expression plot and the cluster plot
      // for the expression plot, use the params as-is (but pass a copy for safety reasons)
      scatterParams.push({ ...exploreParamsWithDefaults })
      // for the cluster plot, we want the same params, but with no genes.
      scatterParams.push({ ...exploreParamsWithDefaults, genes: [] })
    }
  } else {
    // no gene search, just showing clusters
    if (isSpatial) {
      // for spatial non-gene, show the cluster, and then a plot for each spatial cluster
      scatterParams.push({ ...exploreParamsWithDefaults })
      exploreParamsWithDefaults.spatialGroups.forEach(spatialGroup => {
        scatterParams.push({ ...exploreParamsWithDefaults, cluster: spatialGroup })
      })
    } else {
      isTwoColumn = false
      // for non-spatial non-gene, just show the cluster
      scatterParams.push({ ...exploreParamsWithDefaults })
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
  return params.cluster + params.genes?.join('-') + params.annotation.name
}
