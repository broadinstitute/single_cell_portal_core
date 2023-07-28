import React, { useState, useEffect } from 'react'
import _uniqueId from 'lodash/uniqueId'

import { log } from '~/lib/metrics-api'
import PlotUtils from '~/lib/plot'
const getColorBrewerColor = PlotUtils.getColorBrewerColor
import DotPlotLegend from './DotPlotLegend'
import { getAnnotationCellValuesURL, getExpressionHeatmapURL } from '~/lib/scp-api'
import useErrorMessage, { morpheusErrorHandler } from '~/lib/error-message'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { fetchServiceWorkerCache } from '~/lib/service-worker-cache'
import { getSCPContext } from '~/providers/SCPContextProvider'

export const dotPlotColorScheme = {
  // Blue, purple, red.  These red and blue hues are accessible, per WCAG.
  colors: ['#0000BB', '#CC0088', '#FF0000'],

  // TODO: Incorporate expression units, once such metadata is available.
  values: [0, 0.5, 1]
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
   * https://github.com/cmap/morpheus.js/blob/8331b8db8696d1bf3255da2261ac729bfc7ea66a/sw.js#L24
   * to enable service worker cache (SWC) in frontend-only SCP development.
   */
  window.morpheus.BufferedReader.parse = async function(url, options) {
    console.log('from eweitz, in window.morpheus.BufferedReader.parse')
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
      response = fetch(url, fetchOptions)
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
            response = fetch(fileOrUrl, fetchOptions)
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

/** renders a morpheus powered dotPlot for the given URL paths and annotation
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
  subsample, annotationValues
}) {
  const [graphId] = useState(_uniqueId('dotplot-'))
  const { ErrorComponent, showError, setShowError, setErrorContent } = useErrorMessage()
  const expressionValuesURL = getExpressionHeatmapURL({ studyAccession, genes, cluster })
  const annotationCellValuesURL = getAnnotationCellValuesURL({
    studyAccession,
    cluster,
    annotationName: annotation.name,
    annotationScope: annotation.scope,
    annotationType: annotation.type,
    subsample
  })

  useEffect(() => {
    if (annotation.name) {
      performance.mark(`perfTimeStart-${graphId}`)

      log('dot-plot:initialize')
      setShowError(false)
      renderDotPlot({
        target: `#${graphId}`,
        expressionValuesURL,
        annotationCellValuesURL,
        annotationName: annotation.name,
        annotationValues,
        setErrorContent,
        setShowError,
        genes
      })
    }
  }, [
    expressionValuesURL,
    annotationCellValuesURL,
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
function renderDotPlot({
  target, expressionValuesURL, annotationCellValuesURL, annotationName, annotationValues,
  setShowError, setErrorContent, genes
}) {
  const $target = $(target)
  $target.empty()

  // Collapse by mean
  const tools = [{
    name: 'Collapse',
    params: {
      collapse_method: 'Mean',
      shape: 'circle',
      collapse: ['Columns'],
      collapse_to_fields: [annotationName],
      pass_expression: '>',
      pass_value: '0',
      percentile: '100',
      compute_percent: true
    }
  }]

  const config = {
    shape: 'circle',
    dataset: expressionValuesURL,
    el: $target,
    menu: null,
    error: morpheusErrorHandler($target, setShowError, setErrorContent),
    colorScheme: {
      scalingMode: 'relative'
    },
    focus: null,
    tabManager: morpheusTabManager($target),
    tools,
    loadedCallback: () => logMorpheusPerfTime(target, 'dotplot', genes)
  }

  // Load annotations if specified
  if (annotationCellValuesURL !== '') {
    config.columnAnnotations = [{
      file: annotationCellValuesURL,
      datasetField: 'id',
      fileField: 'NAME',
      include: [annotationName]
    }]
    config.columnSortBy = [
      { field: annotationName, order: 0 }
    ]
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
  }

  config.colorScheme = dotPlotColorScheme

  patchServiceWorkerCache()

  // Instantiate dot plot and embed in DOM element
  new window.morpheus.HeatMap(config)
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

/** Log performance timing for Morpheus dot plots and heatmaps */
export function logMorpheusPerfTime(target, plotType, genes) {
  const graphId = target.slice(1) // e.g. #dotplot-1 -> dotplot-1
  performance.measure(graphId, `perfTimeStart-${graphId}`)
  const perfTime = Math.round(
    performance.getEntriesByName(graphId)[0].duration
  )

  log(`plot:${plotType}`, { perfTime, genes })
}
