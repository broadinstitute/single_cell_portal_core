import React, { useState, useEffect } from 'react'
import _uniqueId from 'lodash/uniqueId'
import _remove from 'lodash/remove'
import Plotly from 'plotly.js-dist'
import { Store } from 'react-notifications-component'
import ExifReader from 'exifreader'

import { fetchCluster, updateStudyFile, fetchBucketFile } from '~/lib/scp-api'
import { logScatterPlot } from '~/lib/scp-api-metrics'
import { log } from '~/lib/metrics-api'
import { useUpdateEffect } from '~/hooks/useUpdate'
import PlotTitle from './PlotTitle'

import ScatterPlotLegend from './controls/ScatterPlotLegend'
import useErrorMessage from '~/lib/error-message'
import { computeCorrelations } from '~/lib/stats'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import PlotUtils from '~/lib/plot'
const { getPlotDimensions, filterTrace, getLegendSortedLabels, getColorForLabel, sortTraceByExpression } = PlotUtils
import PlotOptions from './plot-options'
const { defaultScatterColor } = PlotOptions
import LoadingSpinner from '~/lib/LoadingSpinner'
import { formatFileForApi } from '~/components/upload/upload-utils'
import { successNotification, failureNotification } from '~/lib/MessageModal'

window.Plotly = Plotly

/** Renders the appropriate scatter plot for the given study and params
  * @param studyAccession {string} e.g. 'SCP213'
  * @param cluster {string} the name of the cluster, or blank/null for the study's default
  * @param annotation {obj} an object with name, type, and scope attributes
  * @param subsample {string} a string for the subsample to be retrieved.
  * @param consensus {string} for multi-gene expression plots
  * @param dimensionsProps {obj} object with props to determine height and
  *   width, to instruct Plotly how large to render itself. this is useful for
  *   rendering to hidden divs
  * @param isCellSelecting whether plotly's lasso selection tool is enabled
  * @param plotPointsSelected {function} callback for when a user selects points on the plot, which corresponds
  *   to the plotly "points_selected" event
  * @param hiddenTraces {String[]} labels to hide from the plot
  * @param canEdit {Boolean} whether the current user has permissions to edit this study
  */
function RawScatterPlot({
  studyAccession, cluster, annotation, subsample, consensus, genes, scatterColor, dimensionProps,
  isAnnotatedScatter=false, isCorrelatedScatter=false, isCellSelecting=false, plotPointsSelected, dataCache,
  canEdit, bucketId, expressionFilter=[0, 1],
  countsByLabel, setCountsByLabel, hiddenTraces=[], isSplitLabelArrays, updateExploreParams
}) {
  const [isLoading, setIsLoading] = useState(false)
  const [bulkCorrelation, setBulkCorrelation] = useState(null)
  const [labelCorrelations, setLabelCorrelations] = useState(null)
  const [scatterData, setScatterData] = useState(null)
  // array of trace names (strings) to show in the graph
  const [graphElementId] = useState(_uniqueId('study-scatter-'))
  const { ErrorComponent, setShowError, setError } = useErrorMessage()
  const [activeTraceLabel, setActiveTraceLabel] = useState(null)
  // map of label name to color hex codes, for any labels the user has picked a color for
  const [editedCustomColors, setEditedCustomColors] = useState({})
  const [customColors, setCustomColors] = useState({})

  const isRefGroup = getIsRefGroup(scatterData?.annotParams?.type, genes, isCorrelatedScatter)

  const flags = getFeatureFlagsWithDefaults()

  // Uncomment when running Image Pipeline
  // flags.progressive_loading = false
  // TODO (pre-GA for Image Pipeline):
  // - Inspect forthcoming SCP API data for whether static image is available

  const imageClassName = 'scp-canvas-image'
  const imageSelector = `#${ graphElementId } .${imageClassName}`

  /**
   * Handle user interaction with one or more labels in legend.
   *
   * Clicking a label in the legend shows or hides the corresponding set of
   * labeled cells (i.e., the corresponding Plotly.js trace) in the scatter
   * plot.
   */
  function updateHiddenTraces(labels, value, applyToAll=false) {
    let newHiddenTraces
    if (applyToAll) {
      // Handle multi-filter interaction
      newHiddenTraces = (value ? labels : [])
    } else {
      // Handle single-filter interaction
      const label = labels
      newHiddenTraces = [...hiddenTraces]

      if (value && !newHiddenTraces.includes(label)) {
        newHiddenTraces.push(label)
      }
      if (!value) {
        _remove(newHiddenTraces, thisLabel => {return thisLabel === label})
      }
    }

    updateExploreParams({ hiddenTraces: newHiddenTraces })
  }

  /** updates whether pipe-delimited label values should be split */
  function updateIsSplitLabelArrays(value) {
    updateExploreParams({ isSplitLabelArrays: value })
  }

  /** Get new, updated scatter object instance, and new layout */
  function updateScatterLayout(scatter=null) {
    if (!scatter) {
      // New instance forces render of legend (without recomputing traces)
      scatter = Object.assign({}, scatterData)
    }
    const widthAndHeight = getScatterDimensions(scatter, dimensionProps)
    scatter = Object.assign(scatter, widthAndHeight)
    scatter.layout = getPlotlyLayout(scatter)

    return scatter
  }

  /** redraw the plot when editedCustomColors changes */
  useEffect(() => {
    if (editedCustomColors && Object.keys(editedCustomColors).length > 0) {
      const plotlyTraces = document.getElementById(graphElementId).data
      Plotly.react(graphElementId, plotlyTraces, scatterData.layout)
    }
  }, [editedCustomColors])

  /** Save any changes to the legend colors */
  async function saveCustomColors(newColors) {
    const colorObj = {}
    // read the annotation name off of scatterData to ensure it's the real name, and not '' or '_default'
    colorObj[scatterData?.annotParams?.name] = newColors
    const newFileObj = {
      _id: scatterData?.clusterFileId,
      custom_color_updates: colorObj
    }
    setIsLoading(true)
    try {
      const response = await updateStudyFile({
        studyAccession,
        studyFileId: scatterData.clusterFileId,
        studyFileData: formatFileForApi(newFileObj)
      })
      Store.addNotification(successNotification(`Colors saved successfully`))
      const newScatterData = Object.assign({}, scatterData, {
        customColors: response.cluster_file_info?.custom_colors[scatterData.annotParams.name] ?? {}
      })
      setIsLoading(false)
      setScatterData(newScatterData)
      setCustomColors({ ...newColors })
      setEditedCustomColors({ ...newColors })
    } catch (error) {
      Store.addNotification(failureNotification(<span>Error saving colors<br/>{error}</span>))
      setIsLoading(false)
    }
  }

  /** Update layout, without recomputing traces */
  function resizePlot() {
    const scatter = updateScatterLayout()
    Plotly.relayout(graphElementId, scatter.layout)
    setScatterData(scatter)
  }

  /** Update legend counts and recompute traces, without recomputing layout */
  function updateCountsAndGetTraces(scatter) {
    // note that we don't use the previously defined `isRefGroup` constant here, since the value
    // may change as a result of the fetched data, but not be reflected in the isRefGroup constant
    // until `setScatterData` is called
    const isRG = getIsRefGroup(scatter.annotParams.type, genes, isCorrelatedScatter)
    const [traces, labelCounts] = getPlotlyTraces({
      genes,
      isAnnotatedScatter,
      isCorrelatedScatter,
      scatterColor,
      editedCustomColors,
      hiddenTraces: isGeneExpression(genes, isCorrelatedScatter) ? [] : hiddenTraces,
      scatter,
      activeTraceLabel,
      expressionFilter,
      isSplitLabelArrays: isSplitLabelArrays ?? scatter.isSplitLabelArrays,
      isRefGroup: isRG
    })
    if (isRG) {
      setCountsByLabel(labelCounts)
    }
    return traces
  }

  /** Update UI to reflect successful scatter plot rendering */
  function concludeRender(scatter) {
    if (scatter) {
      setScatterData(scatter)
      setCustomColors(scatter.customColors)
    }
    setShowError(false)
    setIsLoading(false)
  }


  /** Fetch cached data from bucket, use it to draw *interactive* gene expression scatter plot */
  function renderBucketData(fetchMethod, expressionParams, dataPath) {
    fetchBucketFile(bucketId, dataPath).then(async response => {
      const expressionArray = await response.json()
      expressionParams.expressionArray = expressionArray
      fetchMethod(expressionParams).then(processScatterPlot).catch(error => {
        setIsLoading(false)
        setShowError(true)
        setError(error)
      })
    })
  }

  /** Draw static image of gene expression scatter plot */
  async function drawPlotImage(response) {
    const imageBuffer = await response.arrayBuffer()
    const exifTags = ExifReader.load(imageBuffer)
    const imageBlob = new Blob([imageBuffer])
    const imageObjectUrl = URL.createObjectURL(imageBlob)

    // Parse gene-specific plot configuration from image Exif metadata
    const ranges = JSON.parse(exifTags.ImageDescription.description)

    // For colorbar labels, and gridlines
    const expressionRange = ranges.expression
    const coordinateRanges = {
      x: ranges.x,
      y: ranges.y,
      z: ranges.z
    }

    // TODO: Move this data from per-gene fetch to cluster fetch
    const titles = {
      x: 'X',
      y: 'Y',
      z: 'Z',
      magnitude: 'Expression'
    }

    const tmpScatterData = Object.assign({}, {
      genes,
      isCorrelatedScatter,
      isAnnotatedScatter,
      axes: {
        titles,
        aspects: null
      },
      data: {
        expression: expressionRange // Only range needed here, not full array
      },
      annotParams: {
        'name': 'General_Celltype',
        'type': 'group',
        'scope': 'study'
      }
    })
    const scatter = updateScatterLayout(tmpScatterData)
    const layout = Object.assign({}, scatter.layout)

    // For gridlines and color bar
    layout.xaxis.range = coordinateRanges.x
    layout.yaxis.range = coordinateRanges.y
    const color = expressionRange

    // TODO: Refactor getPlotlyTraces to return most of these; almost none
    // should need to rely on data fetched per-gene.
    const plotlyTraces = [
      {
        'marker': {
          'line': { 'color': 'rgb(40,40,40)', 'width': 0 },
          'size': 3,
          'showscale': true,
          'colorscale': '',
          'reversescale': false,
          color,
          'colorbar': { 'title': { 'text': titles.magnitude, 'side': 'right' } }
        },
        'x': coordinateRanges.x,
        'y': coordinateRanges.y,
        'mode': 'markers',
        'type': 'scattergl'
      }
    ]
    Plotly.react(graphElementId, plotlyTraces, layout)

    // Replace old mostly-blank WebGL canvas with new "2d" (i.e., non-WebGL) canvas.
    // Only "2d" contexts support the `drawImage` method:
    // https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/drawImage
    const oldCtx = document.querySelector(`#${ graphElementId } .gl-canvas-context`)
    const oldWidth = oldCtx.width
    const oldHeight = oldCtx.height
    oldCtx.remove()
    const canvas = document.createElement('canvas')
    canvas.setAttribute('class', 'gl-canvas gl-canvas-context scp-canvas-image')
    const style = 'position: absolute; top: 0px; left: 0px; overflow: visible; pointer-events: none;'
    canvas.setAttribute('style', style)
    canvas.setAttribute('width', oldWidth)
    canvas.setAttribute('height', oldHeight)
    document.querySelector(`#${ graphElementId } .gl-container`).append(canvas)
    const ctx = document.querySelector(`#${ graphElementId } .gl-canvas-context`).getContext('2d')

    // Load static image of plot, and render it in the canvas element
    const image = new Image()
    image.className = imageClassName
    image.addEventListener('load', renderToCanvas)
    image.width = oldWidth
    image.height = oldHeight
    image.src = imageObjectUrl

    /** Image onload handler.  (Drawing before load renders no image.) */
    function renderToCanvas() {
      // TODO (SCP-4600): Scale and transform scatter plot image on client
      ctx.scale(0.73, 0.73)
      ctx.drawImage(image, 92, 9)
    }

    concludeRender()
  }

  /** Process scatter plot data fetched from server */
  function processScatterPlot(clusterResponse=null) {
    let [scatter, perfTimes] =
      (clusterResponse ? clusterResponse : [scatterData, null])
    scatter = updateScatterLayout(scatter)
    const layout = scatter.layout

    const plotlyTraces = updateCountsAndGetTraces(scatter)

    const startTime = performance.now()

    if (flags?.progressive_loading && genes.length === 1 && document.querySelector(imageSelector)) {
      Plotly.newPlot(graphElementId, plotlyTraces, layout)

      // TODO (SCP-4839): Instrument more bucket cache analytics, then remove console log below
      // console.log(`Interactive plot with bucket data took: ${ Date.now() - window.t0}`)
    } else {
      Plotly.react(graphElementId, plotlyTraces, layout)
    }

    if (perfTimes) {
      perfTimes.plot = performance.now() - startTime
      logScatterPlot({ scatter, genes }, perfTimes)
    }

    if (isCorrelatedScatter) {
      const rhoStartTime = performance.now()

      // Compute correlations asynchronously, to not block other rendering
      computeCorrelations(scatter).then(correlations => {
        const rhoTime = Math.round(performance.now() - rhoStartTime)
        setBulkCorrelation(correlations.bulk)
        if (flags.correlation_refinements) {
          setLabelCorrelations(correlations.byLabel)
        }
        if (perfTimes) {
          log('plot:correlations', { perfTime: rhoTime })
        }
      })
    }

    scatter.hasArrayLabels =
      scatter.annotParams.type === 'group' && scatter.data.annotations.some(annot => annot.includes('|'))

    if (clusterResponse) {
      concludeRender(scatter)
    }
  }

  // Fetches plot data then draws it, upon load or change of any data parameter
  useEffect(() => {
    /** retrieve and process data */
    async function fetchData() {
      setIsLoading(true)

      let expressionArray

      const fetchMethod = dataCache ? dataCache.fetchCluster : fetchCluster

      // use an image and/or data cache if one has been provided, otherwise query scp-api directly
      if (
        flags?.progressive_loading && isGeneExpression(genes, isCorrelatedScatter) && !isAnnotatedScatter &&
        !scatterData
      ) {
        const urlSafeCluster = cluster.replaceAll('+', 'pos').replace(/\W/g, '_')
        const gene = genes[0]
        const stem = '_scp_internal/cache/expression_scatter/'
        const leaf = `${urlSafeCluster}/${gene}`

        // TODO (SCP-4839): Instrument more bucket cache analytics, then remove line below
        // window.t0 = Date.now()

        const imagePath = `${stem}images/${leaf}.webp`
        const dataPath = `${stem}data/${leaf}.json`

        const expressionParams = {
          studyAccession,
          cluster,
          annotation: annotation ? annotation : '',
          subsample,
          consensus,
          genes,
          isAnnotatedScatter,
          isCorrelatedScatter
        }

        fetchBucketFile(bucketId, imagePath).then(async response => {
          const imageCacheHit = response.ok

          // Draw plot as static image first, if it's cached
          if (imageCacheHit) {
            await drawPlotImage(response)
          }

          // Then make it interactive, using gene expression scatter plot data array from GCS bucket
          await renderBucketData(fetchMethod, expressionParams, dataPath)

          // TODO (SCP-4839): Instrument more bucket cache analytics, then remove console log below
          // console.log(`Image render took ${ Date.now() - window.t0}`)
          // Add imageCacheHit boolean to perfTime object here
        })
      } else {
        try {
          // attempt to fetch the data, this will use the cache if available
          const respData1 = await fetchMethod({
            studyAccession,
            cluster,
            annotation: annotation ? annotation : '',
            subsample,
            consensus,
            genes,
            isAnnotatedScatter,
            isCorrelatedScatter,
            expressionArray
          })
          // check that the data contains annotations needed for processing scatterplot
          if (respData1[0]?.data?.annotations?.length) {
            processScatterPlot(respData1)
          } else {
            // if the data was missing the necessary info, make an api call
            const respData = await fetchCluster({
              studyAccession,
              cluster,
              annotation: annotation ? annotation : '',
              subsample,
              consensus,
              genes,
              isAnnotatedScatter,
              isCorrelatedScatter,
              expressionArray
            })
            processScatterPlot(respData)
          }
        } catch (error) {
          setIsLoading(false)
          setShowError(true)
          setError(error)
        }
      }
    }
    fetchData()
  }, [cluster, annotation.name, subsample, genes.join(','), isAnnotatedScatter, consensus])

  useUpdateEffect(() => {
    // Don't update if graph hasn't loaded
    if (scatterData && !isLoading) {
      scatterData.customColors = customColors
      const plotlyTraces = updateCountsAndGetTraces(scatterData)
      Plotly.react(graphElementId, plotlyTraces, scatterData.layout)
    }
    // look for updates of individual properties, so that we don't rerender if the containing array
    // happens to be a different instance
  }, [Object.values(editedCustomColors).join(','),
    Object.values(customColors).join(','), expressionFilter.join(','), isSplitLabelArrays])

  useUpdateEffect(() => {
    // Don't update if graph hasn't loaded
    if (scatterData && !isLoading) {
      const plotlyTraces = document.getElementById(graphElementId).data
      PlotUtils.updateTraceVisibility(plotlyTraces, hiddenTraces)
      // disable autorange so graph does not rescale (SCP-3878)
      // we do not need to explicitly re-enable it since a new cluster will reset the entire layout

      if (scatterData.layout.xaxis) {
        scatterData.layout.xaxis.autorange = false
      }
      if (scatterData.layout.yaxis) {
        scatterData.layout.yaxis.autorange = false
      }
      if (scatterData.layout.zaxis) {
        scatterData.layout.zaxis.autorange = false
      }

      Plotly.react(graphElementId, plotlyTraces, scatterData.layout)
    }
    // look for updates of individual properties, so that we don't rerender if the containing array
    // happens to be a different instance
  }, [hiddenTraces.join(',')])

  useUpdateEffect(() => {
    // Don't update if graph hasn't loaded
    if (scatterData && !isLoading) {
      setIsLoading(true)
      const plotlyTraces = document.getElementById(graphElementId).data
      PlotUtils.sortTraces(plotlyTraces, activeTraceLabel)
      Plotly.react(graphElementId, plotlyTraces, scatterData.layout)
      setIsLoading(false)
    }
  }, [activeTraceLabel])

  // Handles window resizing
  const widthAndHeight = getScatterDimensions(scatterData, dimensionProps, genes)
  useUpdateEffect(() => {
    // Don't update if graph hasn't loaded
    if (scatterData && !isLoading) {
      resizePlot()
    }
  }, [widthAndHeight.height, widthAndHeight.width])

  // Handles Plotly `data` updates, e.g. changes in color profile
  useUpdateEffect(() => {
    // Don't try to update the color if the graph hasn't loaded yet
    if (scatterData && !isLoading) {
      const dataUpdate = { 'marker.colorscale': scatterColor, 'marker.reversescale': shouldReverseScale(scatterColor) }
      Plotly.update(graphElementId, dataUpdate)
    }
  }, [scatterColor])

  // Handles cell select mode updates
  useUpdateEffect(() => {
    // Don't try to update the color if the graph hasn't loaded yet
    if (scatterData && !isLoading) {
      const newDragMode = getDragMode(isCellSelecting)
      Plotly.relayout(graphElementId, { dragmode: newDragMode })
      if (!isCellSelecting) {
        Plotly.restyle(graphElementId, { selectedpoints: [null] })
      }
    }
  }, [isCellSelecting])

  // TODO (SCP-3712): Update legend click (as backwards-compatibly as possible)
  // as part of productionizing custom legend code.
  useEffect(() => {
    const jqScatterGraph = $(`#${graphElementId}`)
    jqScatterGraph.on('plotly_selected', plotPointsSelected)
    return () => {
      jqScatterGraph.off('plotly_selected')
      Plotly.purge(graphElementId)
    }
  }, [])

  return (
    <div className="plot">
      { ErrorComponent }
      <PlotTitle
        cluster={cluster}
        annotation={annotation.name}
        subsample={subsample}
        genes={genes}
        consensus={consensus}
        isCorrelatedScatter={isCorrelatedScatter}
        correlation={bulkCorrelation}/>
      <div
        className="scatter-graph"
        id={graphElementId}
        data-testid={graphElementId}
      >
        { scatterData && countsByLabel && isRefGroup &&
          <ScatterPlotLegend
            name={scatterData.annotParams.name}
            height={scatterData.height}
            countsByLabel={countsByLabel}
            correlations={labelCorrelations}
            hiddenTraces={hiddenTraces}
            updateHiddenTraces={updateHiddenTraces}
            editedCustomColors={editedCustomColors}
            setEditedCustomColors={setEditedCustomColors}
            setCustomColors={setCustomColors}
            saveCustomColors={saveCustomColors}
            customColors={customColors}
            enableColorPicking={canEdit}
            activeTraceLabel={activeTraceLabel}
            setActiveTraceLabel={setActiveTraceLabel}
            hasArrayLabels={scatterData.hasArrayLabels}
            isSplitLabelArrays={isSplitLabelArrays}
            updateIsSplitLabelArrays={updateIsSplitLabelArrays}
            externalLink={scatterData.externalLink}
          />
        }
      </div>
      <p className="help-block">
        { scatterData && scatterData.description &&
          <span>{scatterData.description}</span>
        }
      </p>
      {
        isLoading &&
        <LoadingSpinner testId={`${graphElementId}-loading-icon`}/>
      }
    </div>
  )
}

const ScatterPlot = withErrorBoundary(RawScatterPlot)
export default ScatterPlot

/** Whether this is a gene expression scatter plot */
function isGeneExpression(genes, isCorrelatedScatter) {
  return genes.length && !isCorrelatedScatter
}

/**
 * Whether scatter plot should use custom legend
 *
 * Such legends are used for reference group plots, which are:
 *   A) commonly shown in the default view, and
 *   B) also shown at right in single-gene view
 */
function getIsRefGroup(annotType, genes, isCorrelatedScatter) {
  return annotType === 'group' && !isGeneExpression(genes, isCorrelatedScatter)
}

/** Get width and height for scatter plot dimensions */
function getScatterDimensions(scatter, dimensionProps, genes) {
  // if we don't have a server response yet so we don't know the annotation type,
  // guess based on the number of genes
  let isRefGroup
  if (scatter) {
    isRefGroup = getIsRefGroup(
      scatter.annotParams.type, scatter.genes, scatter.isCorrelatedScatter
    )
  } else {
    isRefGroup = genes.length === 0
  }

  dimensionProps = Object.assign({
    hasLabelLegend: isRefGroup,
    hasTitle: true
  }, dimensionProps)

  return getPlotDimensions(dimensionProps)
}


/** Reverse the continuous colorscale so high contrast color corresponds to high expression */
function shouldReverseScale(scatterColor) {
  // don't reverse the Reds scale, and check whether it is the default
  const shownColor = scatterColor ? scatterColor : defaultScatterColor
  return shownColor !== 'Reds'
}

/** get the array of plotly traces for plotting
 * returns [traces, countsByLabel, isRefGroup]
*/
function getPlotlyTraces({
  genes,
  isAnnotatedScatter,
  isCorrelatedScatter,
  scatterColor,
  editedCustomColors,
  hiddenTraces,
  scatter: {
    axes, data, pointAlpha, pointSize, is3D,
    annotParams: { name: annotName, type: annotType },
    customColors = {}
  },
  activeTraceLabel,
  expressionFilter,
  isSplitLabelArrays,
  isRefGroup
}) {
  const unfilteredTrace = {
    type: is3D ? 'scatter3d' : 'scattergl',
    mode: 'markers',
    x: data.x,
    y: data.y,
    annotations: data.annotations,
    expression: data.expression,
    cells: data.cells,
    opacity: pointAlpha ? pointAlpha : 1
  }
  if (is3D) {
    unfilteredTrace.z = data.z
  }

  const isGeneExpressionForColor = !isCorrelatedScatter && !isAnnotatedScatter && genes.length

  const [traces, countsByLabel, expRange] = filterTrace({
    trace: unfilteredTrace,
    hiddenTraces, groupByAnnotation: isRefGroup, activeTraceLabel,
    expressionFilter, expressionData: data.expression, isSplitLabelArrays
  })

  if (isRefGroup) {
    const labels = getLegendSortedLabels(countsByLabel)
    traces.forEach(groupTrace => {
      groupTrace.type = unfilteredTrace.type
      groupTrace.mode = unfilteredTrace.mode
      groupTrace.opacity = unfilteredTrace.opacity
      const color = getColorForLabel(groupTrace.name, customColors, editedCustomColors, labels.indexOf(groupTrace.name))
      groupTrace.marker = {
        size: pointSize,
        color
      }
    })
  } else {
    // for non-clustered plots, we pass in a single trace with all the points
    let workingTrace = traces[0]
    let colors
    if (isGeneExpressionForColor) {
      workingTrace = sortTraceByExpression(workingTrace)
      colors = workingTrace.expression
    } else {
      colors = isGeneExpressionForColor ? workingTrace.expression : workingTrace.annotations
    }

    workingTrace.marker = {
      line: { color: 'rgb(40,40,40)', width: 0 },
      size: pointSize
    }

    if (!isAnnotatedScatter) {
      const title = isGeneExpressionForColor ? axes.titles.magnitude : annotName

      Object.assign(workingTrace.marker, {
        showscale: true,
        colorscale: scatterColor,
        reversescale: shouldReverseScale(scatterColor),
        color: colors,
        colorbar: { title, titleside: 'right' }
      })

      // if expression values are all zero, set max/min manually so the zeros still look like zero
      // see SCP-2957
      if (genes.length && !colors.some(val => val !== 0)) {
        workingTrace.marker.cmin = 0
        workingTrace.marker.cmax = 1
      } else {
        if (expRange) {
          // if the data was filtered, manually set the range to the unfiltered range
          workingTrace.marker.cmin = expRange[0]
          workingTrace.marker.cmax = expRange[1]
        }
      }
    }
    traces[0] = workingTrace
  }
  traces.forEach(trace => {
    addHoverLabel(trace, annotName, annotType, genes, isAnnotatedScatter, isCorrelatedScatter, axes)
  })

  return [traces, countsByLabel, isRefGroup]
}

/** makes the data trace attributes (cells, trace name) available via hover text */
function addHoverLabel(trace, annotName, annotType, genes, isAnnotatedScatter, isCorrelatedScatter, axes) {
  trace.text = trace.cells
  // use the 'meta' property so annotations are exposed to the hover template
  // see https://community.plotly.com/t/hovertemplate-does-not-show-name-property/36139
  trace.meta = trace.annotations

  let groupHoverTemplate = '(%{x}, %{y})<br><b>%{text}</b><br>%{meta}<extra></extra>'
  if (isAnnotatedScatter) {
    // for annotated scatter, just show coordinates and cell name
    groupHoverTemplate = `(%{x}, %{y})<br>%{text}`
  } else if ((annotType === 'numeric' || genes.length) && !isCorrelatedScatter) {
    // this is a graph with a continuous color scale
    // the bottom row of the hover will either be the expression value, or the annotation value
    const bottomRowLabel = genes.length ? axes.titles.magnitude : annotName
    groupHoverTemplate = `(%{x}, %{y})<br>%{text} (%{meta})<br>${bottomRowLabel}: %{marker.color}<extra></extra>`
  }
  trace.hovertemplate = groupHoverTemplate
}

/** Gets Plotly layout object for scatter plot */
function getPlotlyLayout({
  width,
  height,
  axes,
  userSpecifiedRanges,
  hasCoordinateLabels,
  coordinateLabels,
  isAnnotatedScatter,
  isCorrelatedScatter,
  is3D,
  isCellSelecting=false
}) {
  const layout = {
    hovermode: 'closest',
    dragmode: getDragMode(isCellSelecting)
  }
  if (is3D) {
    layout.scene = get3DScatterProps({
      userSpecifiedRanges, axes, hasCoordinateLabels,
      coordinateLabels
    })
  } else {
    const props2d = get2DScatterProps({
      axes,
      userSpecifiedRanges,
      hasCoordinateLabels,
      coordinateLabels,
      isAnnotatedScatter,
      isCorrelatedScatter
    })
    Object.assign(layout, props2d)
  }

  layout.showlegend = false
  layout.width = width
  layout.height = height
  return layout
}

/** Gets Plotly layout object for two-dimensional scatter plot */
function get2DScatterProps({
  axes,
  userSpecifiedRanges,
  hasCoordinateLabels,
  coordinateLabels,
  isAnnotatedScatter,
  isCorrelatedScatter
}) {
  const { titles } = axes

  const layout = {
    xaxis: { title: titles.x, range: axes?.ranges?.x },
    yaxis: { title: titles.y, range: axes?.ranges?.y }
  }

  if (isAnnotatedScatter === false && isCorrelatedScatter === false) {
    layout.xaxis.showticklabels = false
    layout.yaxis.scaleanchor = 'x'
    layout.yaxis.showticklabels = false
    layout.margin = {
      t: 10,
      r: 0,
      b: 20,
      l: 0
    }
  } else {
    layout.margin = {
      t: 10,
      r: 0,
      b: 50,
      l: 50
    }
  }

  // if user has supplied a range, set that, otherwise let Plotly autorange
  if (userSpecifiedRanges) {
    layout.xaxis.range = userSpecifiedRanges.x
    layout.yaxis.range = userSpecifiedRanges.y
  } else {
    layout.xaxis.autorange = true
    layout.yaxis.autorange = true
  }

  if (hasCoordinateLabels && !isAnnotatedScatter && !isCorrelatedScatter) {
    // don't show coordinate labels on annotated scatters, since the axes are different
    layout.annotations = coordinateLabels
  }

  return layout
}

const baseCamera = {
  up: { x: 0, y: 0, z: 1 },
  center: { x: 0, y: 0, z: 0 },
  eye: { x: 1.25, y: 1.25, z: 1.25 }
}

/** Gets Plotly layout scene props for 3D scatter plot */
function get3DScatterProps({
  userSpecifiedRanges, axes, hasCoordinateLabels,
  coordinateLabels
}) {
  const { titles, aspects } = axes

  const scene = {
    baseCamera,
    aspectmode: 'cube',
    xaxis: { title: titles.x, autorange: true, showticklabels: false },
    yaxis: { title: titles.y, autorange: true, showticklabels: false },
    zaxis: { title: titles.z, autorange: true, showticklabels: false }
  }

  if (userSpecifiedRanges) {
    scene.xaxis.autorange = false
    scene.xaxis.range = userSpecifiedRanges.x
    scene.yaxis.autorange = false
    scene.yaxis.range = userSpecifiedRanges.y
    scene.zaxis.autorange = false
    scene.zaxis.range = userSpecifiedRanges.z
    scene.aspectmode = aspects.mode,
    scene.aspectratio = {
      x: aspects.x,
      y: aspects.y,
      z: aspects.z
    }
  }

  if (hasCoordinateLabels) {
    scene.annotations = coordinateLabels
  }

  return scene
}

/** get the appropriate plotly dragmode option string */
function getDragMode(isCellSelecting) {
  return isCellSelecting ? 'lasso' : 'lasso, select'
}

ScatterPlot.getPlotlyTraces = getPlotlyTraces
