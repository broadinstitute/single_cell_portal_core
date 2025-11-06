import React, { useState, useEffect } from 'react'
import _uniqueId from 'lodash/uniqueId'

import { log } from '~/lib/metrics-api'
import PlotUtils from '~/lib/plot'
const getColorBrewerColor = PlotUtils.getColorBrewerColor
import DotPlotLegend from './DotPlotLegend'
import { getExpressionHeatmapURL, getAnnotationCellValuesURL, fetchMorpheusJson } from '~/lib/scp-api'
import useErrorMessage, { morpheusErrorHandler } from '~/lib/error-message'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import LoadingSpinner, { morpheusLoadingSpinner } from '~/lib/LoadingSpinner'
import { fetchServiceWorkerCache } from '~/lib/service-worker-cache'
import { getSCPContext } from '~/providers/SCPContextProvider'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import '~/lib/dot-plot-precompute-patch'

export const dotPlotColorScheme = {
  // Blue, purple, red.  These red and blue hues are accessible, per WCAG.
  colors: ['#0000BB', '#CC0088', '#FF0000'],
  // TODO: Incorporate expression units, once such metadata is available.
  values: [0, 0.5, 1],
  scalingMode: 'relative'
}

/**
 * Adds rudimentary service worker cache optimization to Morpheus
 *
 * Without SWC, dot plots can take prohibitively long to load in local development
 * for realistic datasets.
 */
function patchServiceWorkerCache() {
  const isServiceWorkerCacheEnabled = getSCPContext().isServiceWorkerCacheEnabled

  /**
   * Monkeypatched from
   * https://github.com/cmap/morpheus.js/blob/8331b8db8696d1bf3255da2261ac729bfc7ea66a/src/io/buffered_reader.js#L36
   * to enable service worker cache (SWC) in frontend-only SCP development.
   */
  window.morpheus.BufferedReader.parse = async function(url, options) {
    const delim = options.delimiter
    const regex = new RegExp(delim)
    const handleTokens = options.handleTokens
    const complete = options.complete
    const fetchOptions = {}
    if (url.headers) {
      for (const header in fetchOptions.headers = new Headers,
      url.headers) {fetchOptions.headers.append(header, url.headers[header])}
    }

    let response
    if (isServiceWorkerCacheEnabled) {
      const fetchSWCacheResult = await fetchServiceWorkerCache(url, fetchOptions)
      response = fetchSWCacheResult[0]
    } else {
      response = await fetch(url, fetchOptions)
    }

    if (response.ok) {
      const reader = response.body.getReader()
      new morpheus.BufferedReader(reader, (line => {
        handleTokens(line.split(regex))
      })
      , (() => {
        complete()
      })
      )
    } else {options.error('Network error')}
  }

  /**
 * Adds rudimentary service worker cache optimization to Morpheus
 *
 * Monkeypatched from:
 * https://github.com/cmap/morpheus.js/blob/8331b8db8696d1bf3255da2261ac729bfc7ea66a/src/util/util.js#L1444
 *
 * @param file
 *            a File or url
 * @return A deferred object that resolves to an array of strings
 */
  window.morpheus.Util.readLines = function(fileOrUrl, interactive) {
    return new Promise((async (resolve, reject) => {
      const isFile = morpheus.Util.isFile(fileOrUrl)
      const isString = morpheus.Util.isString(fileOrUrl)
      const name = morpheus.Util.getFileName(fileOrUrl)
      const ext = morpheus.Util.getExtension(name)

      if (isString) { // URL
        if (ext === 'xlsx') {
          var fetchOptions = {}
          if (fileOrUrl.headers) {
            fetchOptions.headers = new Headers()
            for (const header in fileOrUrl.headers) {
              fetchOptions.headers.append(header, fileOrUrl.headers[header])
            }
          }
          let response
          if (isServiceWorkerCacheEnabled) {
            const fetchSWCacheResult = await fetchServiceWorkerCache(fileOrUrl, fetchOptions)
            response = fetchSWCacheResult[0]
          } else {
            response = fetch(fileOrUrl, fetchOptions)
          }
          let arrayBuffer
          if (response.ok) {
            arrayBuffer = await response.arrayBuffer()
          } else {
            deferred.reject(response)
          }

          if (arrayBuffer) {
            const data = new Uint8Array(arrayBuffer)
            const arr = []
            for (let i = 0; i != data.length; ++i) {
              arr[i] = String.fromCharCode(data[i])
            }
            const bstr = arr.join('')
            morpheus.Util.xlsxTo1dArray({
              data: bstr,
              prompt: interactive
            }, (err, lines) => {
              deferred.resolve(lines)
            })
          } else {
            deferred.reject()
          }
        } else {
          let response
          if (isServiceWorkerCacheEnabled) {
            const fetchSWCacheResult = await fetchServiceWorkerCache(fileOrUrl, fetchOptions)
            response = fetchSWCacheResult[0]
          } else {
            response = await fetch(fileOrUrl, fetchOptions)
          }
          let text
          if (response.ok) {
            text = await response.text()
          }

          resolve(morpheus.Util.splitOnNewLine(text))
        }
      } else if (isFile) {
        const reader = new FileReader()
        reader.onerror = function() {
          console.log('Unable to read file')
          reject('Unable to read file')
        }
        reader.onload = function(event) {
          const arrayBuffer = event.target.result
          const data = new Uint8Array(arrayBuffer)
          if (ext === 'xlsx' || ext === 'xls') {
            const arr = []
            for (let i = 0; i != data.length; ++i) {
              arr[i] = String.fromCharCode(data[i])
            }
            const bstr = arr.join('')
            morpheus.Util
              .xlsxTo1dArray({
                data: bstr,
                prompt: interactive
              }, (err, lines) => {
                resolve(lines)
              })
          } else {
            const br = new morpheus.ArrayBufferReader(data)
            let s
            const lines = []
            const rtrim = /\s+$/
            while ((s = br.readLine()) !== null) {
              const line = s.replace(rtrim, '')
              if (line !== '') {
                lines.push(line)
              }
            }
            resolve(lines)
          }
        }
        reader.readAsArrayBuffer(fileOrUrl)
      } else { // it's already lines?
        resolve(fileOrUrl)
      }
    }))
  }
}

/** Renders a Morpheus-powered dot plot for the given URL paths and annotation
  * Note that this has a lot in common with Heatmap.js.  they are separate for now
  * as their display capabilities may diverge (esp. since DotPlot is used in global gene search)
  * @param cluster {string} the name of the cluster, or blank/null for the study's default
  * @param annotation {obj} an object with name, type, and scope attributes
  * @param subsample {string} a string for the subsample to be retrieved.
  * @param consensus {string} for multi-gene expression plots
  * @param dimensions {obj} object with height and width, to instruct plotly how large to render itself
  */
function RawDotPlot({
  studyAccession, genes=[], cluster, annotation={},
  subsample, annotationValues, setMorpheusData
}) {
  const [graphId] = useState(_uniqueId('dotplot-'))
  const { ErrorComponent, showError, setShowError, setErrorContent } = useErrorMessage()

  useEffect(() => {
    /** Fetch Morpheus data for dot plot */
    async function getDataset() {
      const flags = getFeatureFlagsWithDefaults()
      const usePrecomputed = flags?.dot_plot_preprocessing_frontend || false
      
      const [dataset, perfTimes] = await fetchMorpheusJson(
        studyAccession,
        genes,
        cluster,
        annotation.name,
        annotation.type,
        annotation.scope,
        subsample,
        usePrecomputed
      )
      logFetchMorpheusDataset(perfTimes, cluster, annotation, genes)

      return dataset
    }
    if (annotation.name) {
      // put spinner up manually
      const target = `#${graphId}`
      $(target).empty()
      $(target).html(morpheusLoadingSpinner())

      getDataset().then(dataset => {
        performance.mark(`perfTimeStart-${graphId}`)
        log('dot-plot:initialize')
        setShowError(false)
        renderDotPlot({
          target,
          dataset,
          annotationName: annotation.name,
          annotationValues,
          setErrorContent,
          setShowError,
          genes
        })
        setMorpheusData(dataset)
      })
    }
  }, [
    cluster,
    genes.join(','),
    annotation.name,
    annotation.scope
  ])

  return (
    <div>
      { ErrorComponent }
      { cluster &&
      <>
        <div id={graphId} className="dotplot-graph"></div>
        { !showError && <DotPlotLegend/> }
      </> }
      { !cluster && <LoadingSpinner/> }
    </div>
  )
}

const DotPlot = withErrorBoundary(RawDotPlot)
export default DotPlot

/** Render Morpheus dot plot */
export function renderDotPlot({
  target, dataset, annotationName, annotationValues,
  setShowError, setErrorContent, genes, drawCallback
}) {
  console.log('in renderDotPlot, dataset', dataset)

  const $target = $(target)
  $target.empty()

  // Check if dataset is pre-computed dot plot data
  // Pre-computed data has structure: { annotation_name, values, genes }
  let processedDataset = dataset
  let isPrecomputed = false

  if (dataset && dataset.annotation_name && dataset.values && dataset.genes) {
    // This is pre-computed dot plot data - convert it using the patch
    console.log('Detected pre-computed dot plot data, converting...')
    processedDataset = window.createMorpheusDotPlot(dataset)
    isPrecomputed = true
    console.log('Converted dataset:', processedDataset)
    console.log('Dataset series count:', processedDataset.getSeriesCount())
    for (let i = 0; i < processedDataset.getSeriesCount(); i++) {
      console.log(`  Series ${i} name:`, processedDataset.getName(i))
    }
  }

  // Collapse by mean (only for non-precomputed data)
  const tools = isPrecomputed ? [] : [{
    name: 'Collapse',
    params: {
      collapse_method: 'Mean',
      shape: 'circle',
      collapse: ['Columns'],
      collapse_to_fields: [annotationName],
      pass_expression: '>',
      pass_value: '0',
      percentile: '75',
      compute_percent: true
    }
  }]

  const config = {
    shape: 'circle',
    dataset: processedDataset,
    el: $target,
    menu: null,
    error: morpheusErrorHandler($target, setShowError, setErrorContent),
    focus: null,
    tabManager: morpheusTabManager($target),
    tools,
    loadedCallback: () => logMorpheusPerfTime(target, 'dotplot', genes)
  }

  // For pre-computed data, tell Morpheus to display series 0 for color
  // and use series 1 for sizing (which happens automatically with shape: 'circle')
  if (isPrecomputed) {
    config.symmetricColorScheme = false
    // Tell Morpheus which series to use for coloring the heatmap
    config.seriesIndex = 0 // Display series 0 (Mean Expression) for colors
    // Explicitly set the size series
    config.sizeBySeriesIndex = 1 // Use series 1 (__count) for sizing
  }

  // Load annotations if specified
  // config.columnSortBy = [
  //   { field: annotationName, order: 0 }
  // ]
  config.columns = [
    { field: annotationName, display: 'text' }
  ]
  config.rows = [
    { field: 'id', display: 'text' }
  ]

  // Create mapping of selected annotations to colorBrewer colors
  const annotColorModel = {}
  annotColorModel[annotationName] = {}
  const sortedAnnots = annotationValues.sort()

  // Calling % 27 will always return to the beginning of colorBrewerSet
  // once we use all 27 values
  $(sortedAnnots).each((index, annot) => {
    annotColorModel[annotationName][annot] = getColorBrewerColor(index)
  })
  config.columnColorModel = annotColorModel


  // Set color scheme (will be overridden for precomputed data below)
  if (!isPrecomputed) {
    config.colorScheme = dotPlotColorScheme
  }

  // For precomputed data, configure the sizer to use the __count series
  if (isPrecomputed && processedDataset) {
    // The color scheme should already have a sizer - we just need to configure it
    config.sizeBy = {
      seriesName: 'percent',
      min: 0,
      max: 75
    }

    // Use relative color scheme for raw expression values
    // This will scale colors based on the actual data range across all genes and cell types
    config.colorScheme = {
      colors: ['#0000BB', '#CC0088', '#FF0000'],
      values: [0, 0.5, 1],
      scalingMode: 'relative'
    }
  }

  patchServiceWorkerCache()

  config.drawCallback = function() {
    const dotPlot = this

    // Debug for precomputed data
    if (isPrecomputed) {
      console.log('Dot plot instance:', dotPlot)
      console.log('Dot plot project:', dotPlot.project)
      console.log('Dot plot options:', dotPlot.options)
      if (dotPlot.heatMapElementCanvas) {
        console.log('HeatMapElementCanvas:', dotPlot.heatMapElementCanvas)
        console.log('Shape:', dotPlot.heatMapElementCanvas.shape)
        console.log('Color scheme:', dotPlot.heatMapElementCanvas.colorScheme)
        console.log('Series index for color:', dotPlot.heatMapElementCanvas.getColorScheme().seriesIndex)
        
        // Check actual data values
        const dataset = dotPlot.project.getSortedFilteredDataset()
        console.log('Dataset row count:', dataset.getRowCount())
        console.log('Dataset column count:', dataset.getColumnCount())
        console.log('Dataset series count:', dataset.getSeriesCount())
        
        // Sample some values
        if (dataset.getRowCount() > 0 && dataset.getColumnCount() > 0) {
          console.log('Sample values (row 0, all columns, series 0):')
          for (let j = 0; j < Math.min(5, dataset.getColumnCount()); j++) {
            console.log(`  [0,${j},0] =`, dataset.getValue(0, j, 0))
          }
        }
      }
    }

    if (drawCallback) {drawCallback(dotPlot)}
  }

  // Instantiate dot plot and embed in DOM element
  console.log('Dot plot config:', config)
  delete window.dotPlot
  window.dotPlot = new window.morpheus.HeatMap(config)
}

/** return a trivial tab manager that handles focus and sizing
 * We implement our own trivial tab manager as it seems to be the only way
 * (after 2+ hours of digging) to prevent morpheus auto-scrolling
 * to a heatmap once it's rendered
 */
export function morpheusTabManager($target) {
  return {
    add: options => {
      $target.empty()
      $target.append(options.$el)
      return { id: $target.attr('id'), $panel: $target }
    },
    setTabTitle: () => {},
    setActiveTab: () => {},
    getActiveTabId: () => {},
    getWidth: () => $target.actual('width'),
    getHeight: () => $target.actual('height'),
    getTabCount: () => 1
  }
}

/** Log render performance timing for Morpheus dot plots and heatmaps */
export function logMorpheusPerfTime(target, plotType, genes) {
  const graphId = target.slice(1) // e.g. #dotplot-1 -> dotplot-1
  performance.measure(graphId, `perfTimeStart-${graphId}`)
  const perfTime = Math.round(
    performance.getEntriesByName(graphId)[0].duration
  )

  log(`plot:${plotType}`, { perfTime, genes })
}

/** Log performance of loading JSON datasets for Morpheus */
export function logFetchMorpheusDataset(perfTimes, cluster, annotation, genes) {
  const props = {
    perfTimes,
    cluster,
    annotName: annotation.name,
    annotType: annotation.type,
    annotScope: annotation.scope,
    genes
  }
  log(`dot-plot:dataset`, props)
}
