/**
 * @fileoverview Overlays expression summary graphics on genes in pathway diagram
 *
 * This augments pathway diagrams shown via related genes ideogram.  Ideogram renders
 * a pathway diagram with some basic coloring, then code in this module enriches it.
 * Expression metrics, i.e. "scaled mean expression" and "percent of cells expressing",
 * are retrieved from Morpheus dot plot methods and associated SCP API endpoints.
 * Those expression metrics are available for each (annotation label, gene) tuple.
 *
 * Upon fetching the metrics, each gene in the pathway is colored by mean expression, and
 * its contrast is adjusted by percent of cells expressing.  This "expression overlay"
 * essentially shows the same metrics as a dot plot, but for one annotation label at a time,
 * and with the major added benefit of showing a rich knowledge graph: specific directed
 * interactions among networks of genes in detailed molecular biology context.
 *
 * More background and demo video are available at:
 * https://github.com/broadinstitute/single_cell_portal_core/pull/2104
 */

import { renderDotPlot } from '~/components/visualization/DotPlot'
import { getEligibleLabels } from '~/lib/cluster-utils'
import { fetchMorpheusJson } from '~/lib/scp-api'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

// Denoise DevTools console log by not showing error that lacks user impact
window.onerror = function(error) {
  if (error.includes(`Failed to execute 'inverse' on 'SVGMatrix': The matrix is not invertible.`)) {
    console.debug(
      'Suppress non-user-impacting Pvjs error due to resize when showing pathway diagram'
    )
    return true
  }
}

const loadingCls = 'pathway-loading-expression'

/**
 * Get mean, percent, and color per gene, by annotation label
 *
 * For scRNA-seq:
 * - Mean: average expression value
 * - Percent: percent of cells expressing
 * - Color: hex value for color of scaled mean expression: blue low, purple medium, red high
 */
export function getDotPlotMetrics(dotPlot) {
  const metrics = {}

  const colorScheme = dotPlot.getColorScheme()

  const dataset = dotPlot.dataset
  const labels = dataset.columnMetadata.vectors[0].array
  const genes = dataset.rowMetadata.vectors[0].array

  for (let i = 0; i < labels.length; i++) {
    const label = labels[i]
    const labelIndex = i
    metrics[label] = {}
    for (let j = 0; j < genes.length; j++) {
      const gene = genes[j]
      const geneIndex = j
      try {
        const mean = dataset.getValue(geneIndex, labelIndex, 0)
        const percent = dataset.getValue(geneIndex, labelIndex, 1)
        const color = colorScheme.getColor(geneIndex, labelIndex, mean)
        metrics[label][gene] = { mean, percent, color }
      } catch (error) {
        // eslint-disable-next-line quotes
        if (error.message === "Cannot read properties of undefined (reading 'getValue')") {
          // Occurs upon resizing window, artifact of internal Morpheus handling
          // of pre-dot-plot heatmap matrix.  No user-facing impact.
          return null
        }
      }
    }
  }

  return metrics
}

window.SCP.renderBackgroundDotPlotRegister = {}

/** Render undisplayed Morpheus dot plot, to get metrics for pathway diagram */
export async function renderBackgroundDotPlot(
  studyAccession, genes=[], cluster, annotation={},
  subsample, annotationValues, drawCallback,
  topContainerSelector
) {
  const graphId = 'background-dot-plot'
  document.querySelector(`#${graphId}`)?.remove()

  const registerKey = [
    studyAccession,
    genes.join(','),
    cluster,
    annotation.name,
    annotation.type,
    annotation.scope,
    subsample
  ].join('--')

  // Prevent duplicate parallel requests of the same dot plot
  if (registerKey in window.SCP.renderBackgroundDotPlotRegister) {
    return
  }
  window.SCP.renderBackgroundDotPlotRegister[registerKey] = 1

  const topContainer = document.querySelector(topContainerSelector)

  const container = `<div id="${graphId}" style="display: none;">`

  topContainer.insertAdjacentHTML('beforeEnd', container)
  const target = `#${graphId}`

  performance.mark(`perfTimeStart-${graphId}`)
  let dataset

  try {
    const results = await fetchMorpheusJson(
      studyAccession,
      genes,
      cluster,
      annotation.name,
      annotation.type,
      annotation.scope,
      subsample
    )
    dataset = results[0]

    // Don't prevent non-parallel duplicate requests
    delete window.SCP.renderBackgroundDotPlotRegister[registerKey]
  } catch (error) {
    delete window.SCP.renderBackgroundDotPlotRegister[registerKey]
  }

  renderDotPlot({
    target,
    dataset,
    annotationName: annotation.name,
    annotationValues,
    setErrorContent: () => {},
    setShowError: () => {},
    genes,
    drawCallback
  })
}

/** Get unique genes in pathway diagram, ranked by global interest */
export function getPathwayGenes() {
  const ranks = window.Ideogram.geneCache.interestingNames
  const dataNodes = Array.from(document.querySelectorAll('#_ideogramPathwayContainer g.DataNode'))
  const geneNodes = []
  for (let i = 0; i < dataNodes.length; i++) {
    const dataNode = dataNodes[i]
    const classes = dataNode.classList

    for (let j = 0; j < classes.length; j++) {
      const cls = classes[j]
      const isGene = ['geneproduct', 'rna', 'protein'].includes(cls.toLowerCase())
      if (isGene) {
        geneNodes.push(dataNode)
        break
      }
    }
  }

  const genes = geneNodes.map(
    node => {return { domId: node.id, name: node.querySelector('text').textContent }}
  )

  const rankedGenes = genes
    .filter(gene => ranks.includes(gene.name))
    .sort((a, b) => ranks.indexOf(a.name) - ranks.indexOf(b.name))

  return rankedGenes
}

/** Slice array into batches of a given size */
function sliceIntoBatches(arr, batchSize) {
  const result = []
  for (let i = 0; i < arr.length; i += batchSize) {
    result.push(arr.slice(i, i + batchSize))
  }
  return result
}

/** Get genes from pathway, in batches of up to 50 genes, eliminating duplicates */
export function getDotPlotGeneBatches(pathwayGenes) {
  const genes = pathwayGenes.map(g => g.name)
  const uniqueGenes = Array.from(new Set(genes))

  const dotPlotGeneBatches = sliceIntoBatches(uniqueGenes, 50)

  return dotPlotGeneBatches
}

/**
 * Color each gene red/purple/blue by mean expression, and
 * set each gene's contrast by percent of cells expression
 */
export function colorPathwayGenesByExpression(annotationLabel, dotPlotMetrics) {
  const genes = getPathwayGenes()

  const styleRulesets = []
  const unassayedGenes = []

  const metricsByLabel = dotPlotMetrics[annotationLabel]

  if (!metricsByLabel) {
    return
  }

  genes.forEach(geneObj => {
    const domId = geneObj.domId
    const gene = geneObj.name
    const metrics = metricsByLabel[gene]

    if (!metrics) {
      unassayedGenes.push(gene)
      return
    }

    const baseSelector = `#_ideogramPathwayContainer .DataNode#${domId}`
    const rect = document.querySelector(`${baseSelector} rect`)
    if (!rect) {
      // Can happen when resizing and pathway DOM nodes are transiently unavailable
      return
    }

    const percent = metrics.percent

    // Higher `colorPercent`, higher contrast.  Lowering visual prominence by
    // decreasing contrast in these pathway nodes is analogous to how dot
    // plots lower visual prominence by decreasing size in circle nodes.
    // Adjusting node size in pathways isn't feasible because the nodes also
    // contain shown labels, and pathway graphics layout is sensitive to
    // node size.
    const colorPercent = Math.min(percent < 75 ? percent : percent + 25, 100)

    const textColor = percent < 50 ? 'black' : 'white'

    // Docs: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix
    const rectColor = `color-mix(in oklab, ${metrics.color} ${colorPercent}%, white)`

    const rectRuleset = `${baseSelector} rect {fill: ${rectColor};}`
    const textRuleset = `${baseSelector} text {fill: ${textColor};}`
    const rulesets = `${rectRuleset} ${textRuleset}`

    rect.setAttribute('data-scaled-mean-expression', metrics.mean)
    rect.setAttribute('data-percent-expressing', percent)

    styleRulesets.push(rulesets)
  })

  const style = `<style class="ideo-pathway-style">${styleRulesets.join(' ')}</style>`
  const pathwayContainer = document.querySelector('#_ideogramPathwayContainer')

  if (unassayedGenes.length > 0) {
    // This might help to eventually convey in hover text, etc.
    console.debug(`Genes omitted due to dot plot restrictions, or not assayed in study: ${unassayedGenes.join(', ')}`)
  }

  document.querySelector('.ideo-pathway-style')?.remove()
  pathwayContainer.insertAdjacentHTML('afterbegin', style)
}

/** Get dropdown menu of annotation labels; pick one to color genes */
function writePathwayAnnotationLabelMenu(label, dotPlotMetrics) {
  // const options = labels.map(label => `<option>${label}</option>`)
  const menu =
    `<span class="pathway-label-menu-container" style="margin-left: 10px;">` +
      `| Colored by expression in: <span class="pathway-label-menu">${label}</span>` +
    `</span>`
  const headerLink = document.querySelector('._ideoPathwayHeader a')
  document.querySelector('.pathway-label-menu-container')?.remove()
  headerLink.insertAdjacentHTML('afterend', menu)
  const menuSelectDom = document.querySelector('.pathway-label-menu')
  menuSelectDom.addEventListener('change', () => {
    const newLabel = menuSelectDom.value
    colorPathwayGenesByExpression(newLabel, dotPlotMetrics)
  })
}

/** Update pathway header with SCP label menu, info icon */
function writePathwayExpressionHeader(dotPlotMetrics, label, pathwayGenes) {
  // Remove "Loading expression...", as load is done
  document.querySelector(`.${loadingCls}`)?.remove()

  // writePathwayExpressionLegend()
  writePathwayAnnotationLabelMenu(label, pathwayGenes, dotPlotMetrics)
}

/** Add "Loading expression..." to pathway header while dot plot metrics are being fetched */
export function writeLoadingIndicator() {
  document.querySelector('.pathway-label-menu-container')?.remove()
  const headerLink = document.querySelector('._ideoPathwayHeader a')
  if (!headerLink) {
    return
  }
  const style = 'color: #777; font-style: italic; margin-left: 10px;'
  const loading = `<span class="${loadingCls}" style="${style}">Loading expression...</span>`
  document.querySelector(`.${loadingCls}`)?.remove()
  headerLink.insertAdjacentHTML('afterend', loading)
}

/** Merge new and old dot plots metrics */
function mergeDotPlotMetrics(newMetrics, oldMetrics) {
  Object.entries(oldMetrics).map(([label, oldGeneMetrics]) => {
    const newGeneMetrics = newMetrics[label]
    if (!newGeneMetrics) {
      return
    }
    newMetrics[label] = Object.assign(newGeneMetrics, oldGeneMetrics)
  })

  return newMetrics
}

/** Color pathway gene nodes by expression */
export async function renderPathwayExpression(studyAccession, cluster, annotation, label, labels) {
  let allDotPlotMetrics = {}

  const pathwayGenes = getPathwayGenes()
  const dotPlotGeneBatches = getDotPlotGeneBatches(pathwayGenes)

  let numDraws = 0
  let numRenders = 0

  const annotationLabels = getEligibleLabels()

  if (label === '') {
    return
  }

  /** After invisible dot plot renders, color each gene by expression metrics */
  function backgroundDotPlotDrawCallback(dotPlot) {
    // The first render is for uncollapsed cell-x-gene metrics (heatmap),
    // the second render is for collapsed label-x-gene metrics (dotplot)

    numDraws += 1
    if (numDraws === 1) {return}

    const dotPlotMetrics = getDotPlotMetrics(dotPlot)

    if (!dotPlotMetrics) {
      // Occurs upon resizing window, artifact of internal Morpheus handling
      // of pre-dot-plot heatmap matrix.  No user-facing impact.
      return
    }

    const dotPlotMetricsKeys = Object.keys(dotPlotMetrics)
    if (!labels || !labels.includes(dotPlotMetricsKeys[0])) {
      // Another protection for computing only for dot plots, not heatmaps
      return
    }

    allDotPlotMetrics = mergeDotPlotMetrics(dotPlotMetrics, allDotPlotMetrics)

    writePathwayExpressionHeader(allDotPlotMetrics, label, pathwayGenes)

    colorPathwayGenesByExpression(label, allDotPlotMetrics)

    if (numRenders < dotPlotGeneBatches.length - 1) {
      numRenders += 1
      // Future optimization: render background dot plot one annotation at a time.  This would
      // speed up initial pathway expression overlay rendering, and increase the practical limit
      // on number of genes that could be retrieved via SCP API Morpheus endpoint.
      renderBackgroundDotPlot(
        studyAccession, dotPlotGeneBatches[numRenders], cluster, annotation,
        'All', annotationLabels, backgroundDotPlotDrawCallback,
        '#_ideogramPathwayContainer'
      )
    }
  }

  // Future optimization: render background dot plot one annotation at a time.  This would
  // speed up initial pathway expression overlay rendering, and increase the practical limit
  // on number of genes that could be retrieved via SCP API Morpheus endpoint.
  renderBackgroundDotPlot(
    studyAccession, dotPlotGeneBatches[0], cluster, annotation,
    'All', annotationLabels, backgroundDotPlotDrawCallback,
    '#_ideogramPathwayContainer'
  )
}

/** Draw expression overlay in pathway diagram */
function drawPathwayOverlay(event, studyAccession, cluster, annotation, label, labels) {

  // Hide popover instantly upon drawing pathway; don't wait ~2 seconds
  const ideoTooltip = document.querySelector('._ideogramTooltip')
  if (ideoTooltip) {
    ideoTooltip.style.opacity = 0
    ideoTooltip.style.pointerEvents = 'none'
  }

  // Ensure popover for pathway diagram doesn't appear over gene search autocomplete,
  // while still appearing over default visualizations.
  const container = document.querySelector('#_ideogramPathwayContainer')
  container.style.zIndex = 2

  const details = event.detail
  const searchedGene = details.sourceGene
  const interactingGene = details.destGene

  renderPathwayExpression(studyAccession, cluster, annotation, label, labels)
}

/** Removeable event listener */
function callDrawPathwayOverlay(event) {
  const {
    studyAccession, cluster, annotation, label, labels
  } = window.Ideogram.SCP.pathway

  drawPathwayOverlay(
    event,
    studyAccession, cluster, annotation, label, labels
  )
  document.removeEventListener('ideogramDrawPathway', callDrawPathwayOverlay)
}

/**
 * Add and remove event listeners for Ideogram's `ideogramDrawPathway` event
 *
 * This sets up the pathway expression overlay
 */
export function manageDrawPathway(studyAccession, cluster, annotation, label, labels) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.show_pathway_expression) {return}

  if (!window.Ideogram.SCP) {
    window.Ideogram.SCP = {};
  }
  window.Ideogram.SCP.pathway = {
    studyAccession, cluster, annotation, label, labels
  }

  if (annotation.type === 'group') {
    document.removeEventListener('ideogramDrawPathway', callDrawPathwayOverlay)
    document.addEventListener('ideogramDrawPathway', callDrawPathwayOverlay)
  }
}
