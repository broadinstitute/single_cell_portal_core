/**
 * @fileoverview Overlays expression summary metrics on genes in pathway diagram
 *
 * This augments pathway diagrams shown via related genes ideogram.  Ideogram renders
 * a pathway diagram with some basic coloring, then code in this module enriches it.
 * Expression metrics, i.e. "scaled mean expression" and "percent of cells expressing",
 * are retrieved from Morpheus dot plot methods and associated SCP API endpoints.
 * Those expression metrics are available for each (annotation label, gene) tuple.
 *
 * Upon fetching the metrics, each gene in the pathway is colored by mean expression, and
 * its opacity is adjusted by percent of cells expressing.  This "expression overlay"
 * essentially shows the same metrics as a dot plot, but for one annotation label at a time,
 * and with the major added benefit of showing a rich knowledge graphs: specific directed
 * interactions among networks of genes in molecular biology context.
 *
 * More background and demo video are available at:
 * https://github.com/broadinstitute/single_cell_portal_core/pull/2104
 */

import { renderBackgroundDotPlot, getDotPlotMetrics } from '~/components/visualization/DotPlot'
import { getAnnotationValues } from '~/lib/cluster-utils'

/** Get unique genes in pathway diagram, ranked by global interest */
function getPathwayGenes(ideogram) {
  const dataNodes = Array.from(document.querySelectorAll('#_ideogramPathwayContainer g.DataNode'))
  const geneNodes = dataNodes.filter(
    dataNode => Array.from(dataNode.classList).some(cls => cls.startsWith('Ensembl_ENS'))
  )
  const genes = geneNodes.map(
    node => {return { domId: node.id, name: node.querySelector('text').textContent }}
  )
  const ranks = ideogram.geneCache.interestingNames
  const rankedGenes = genes
    .filter(gene => ranks.includes(gene.name))
    .sort((a, b) => ranks.indexOf(a.name) - ranks.indexOf(b.name))
  return rankedGenes
}

/** Get 50 genes from pathway, including searched gene and interacting gene */
function getDotPlotGenes(searchedGene, interactingGene, pathwayGenes, ideogram) {
  const genes = pathwayGenes.map(g => g.name)
  const uniqueGenes = Array.from(new Set(genes))
  const dotPlotGenes = uniqueGenes.slice(0, 50)
  if (!dotPlotGenes.includes(searchedGene)) {
    dotPlotGenes[dotPlotGenes.length - 2] = searchedGene
  }
  if (!dotPlotGenes.includes(interactingGene)) {
    dotPlotGenes[dotPlotGenes.length - 1] = interactingGene
  }

  return dotPlotGenes
}

/** Color genes by expression dot plot */
function colorPathwayGenesByExpression(genes, dotPlotMetrics, annotationLabel) {
  const styleRulesets = []
  const unassayedGenes = []
  genes.forEach(geneObj => {
    const domId = geneObj.domId
    const gene = geneObj.name
    const metrics = dotPlotMetrics[annotationLabel][gene]
    if (!metrics) {
      unassayedGenes.push(gene)
      return
    }
    const color = metrics.color
    const opacity = metrics.percent + 0.25
    const baseSelector = `#_ideogramPathwayContainer .DataNode#${domId}`
    const rectRuleset = `${baseSelector} rect {fill: ${color}; opacity: ${opacity};}`
    const textRuleset = `${baseSelector} text {fill: white;}`
    const rulesets = `${rectRuleset} ${textRuleset}`
    styleRulesets.push(rulesets)
  })
  const style = `<style class="ideo-pathway-style">${styleRulesets.join(' ')}</style>`
  const pathwayContainer = document.querySelector('#_ideogramPathwayContainer')
  if (unassayedGenes.length > 0) {
    // This might help to eventually convey in hover text, etc.
    console.debug(`Study did not assay these genes in pathway: ${unassayedGenes.join(', ')}`)
  }
  const prevStyle = document.querySelector('.ideo-pathway-style')
  if (prevStyle) {prevStyle.remove()}
  pathwayContainer.insertAdjacentHTML('afterbegin', style)
}

// TODO (SCP-5760): Replace this React FontAwesome Icon upon refactoring to React
// eslint-disable-next-line max-len
const infoIcon = `<svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="info-circle" class="svg-inline--fa fa-info-circle " role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#3D5A87" d="M256 8C119.043 8 8 119.083 8 256c0 136.997 111.043 248 248 248s248-111.003 248-248C504 119.083 392.957 8 256 8zm0 110c23.196 0 42 18.804 42 42s-18.804 42-42 42-42-18.804-42-42 18.804-42 42-42zm56 254c0 6.627-5.373 12-12 12h-88c-6.627 0-12-5.373-12-12v-24c0-6.627 5.373-12 12-12h12v-64h-12c-6.627 0-12-5.373-12-12v-24c0-6.627 5.373-12 12-12h64c6.627 0 12 5.373 12 12v100h12c6.627 0 12 5.373 12 12v24z"></path></svg>`

/** Write brief icon explaining color and opacity */
function writePathwayExpressionLegend() {
  const legendText =
    'Color represents scaled mean expression: red is high, purple medium, blue low.  ' +
    'Opacity represents percent of cells expressing: higher % is more opaque, lower more transparent.'
  const legendAttrs =
    `class="pathway-legend" style="margin-left: 10px;" ` +
    `data-toggle="tooltip" data-original-title="${legendText}"`
  const legend = `<span ${legendAttrs}>${infoIcon}</span>`
  const headerLink = document.querySelector('._ideoPathwayHeader a')
  const prevElement = document.querySelector('.pathway-legend')
  if (prevElement) {prevElement.remove()}
  headerLink.insertAdjacentHTML('afterend', legend)
}


/** Get dropdown menu of annotation labels; pick one to color genes */
function writePathwayAnnotationLabelMenu(labels, pathwayGenes, dotPlotMetrics) {

  const options = labels.map(label => `<option>${label}</option>`)
  const menu =
    `<span class="pathway-label-menu-container" style="margin-left: 10px;">` +
      `<label>Expression in:</label> <select class="pathway-label-menu">${options.join()}</select>` +
    `</span>`
  const headerLink = document.querySelector('._ideoPathwayHeader a')
  const prevElement = document.querySelector('.pathway-label-menu-container')
  if (prevElement) {prevElement.remove()}
  headerLink.insertAdjacentHTML('afterend', menu)
  const menuSelectDom = document.querySelector('.pathway-label-menu')
  menuSelectDom.addEventListener('change', () => {
    const newLabel = menuSelectDom.value
    colorPathwayGenesByExpression(pathwayGenes, dotPlotMetrics, newLabel)
  })
}

/** Color pathway gene nodes by expression */
function renderPathwayExpression(
  searchedGene, interactingGene,
  ideogram, dotPlotParams
) {
  const pathwayGenes = getPathwayGenes(ideogram)
  const dotPlotGenes = getDotPlotGenes(searchedGene, interactingGene, pathwayGenes, ideogram)

  const { studyAccession, cluster, annotation } = dotPlotParams

  let numDraws = 0

  const exploreParamsWithDefaults = window.SCP.exploreParamsWithDefaults
  const exploreInfo = window.SCP.exploreInfo
  const countsByLabel = window.SCP.countsByLabel

  const rawAnnotLabels = getAnnotationValues(
    exploreParamsWithDefaults?.annotation,
    exploreInfo?.annotationList
  )
  const annotationLabels = rawAnnotLabels.filter(label => countsByLabel[label] > 0)

  const loadingCls = 'pathway-loading-expression'
  const headerLink = document.querySelector('._ideoPathwayHeader a')
  const loading = `<span class="${loadingCls}" style="color: #555; margin-left: 10px;">Loading expression...</span>`
  const prevElement = document.querySelector(`.${loadingCls}`)
  if (prevElement) {prevElement.remove()}
  headerLink.insertAdjacentHTML('afterend', loading)

  /** After invisible dot plot renders, color each gene by expression metrics */
  function backgroundDotPlotDrawCallback(dotPlot) {
    // The first render is for uncollapsed cell-x-gene metrics (heatmap),
    // the second render is for collapsed label-x-gene metrics (dotplot)
    numDraws += 1
    if (numDraws === 1) {return}

    // Remove "Loading expression..."
    document.querySelector(`.${loadingCls}`).remove()

    const dotPlotMetrics = getDotPlotMetrics(dotPlot)
    writePathwayExpressionLegend()
    writePathwayAnnotationLabelMenu(annotationLabels, pathwayGenes, dotPlotMetrics)

    const annotationLabel = annotationLabels[0]
    colorPathwayGenesByExpression(pathwayGenes, dotPlotMetrics, annotationLabel)
  }

  renderBackgroundDotPlot(
    studyAccession, dotPlotGenes, cluster, annotation,
    'All', annotationLabels, backgroundDotPlotDrawCallback,
    '#related-genes-ideogram-container'
  )
}

/**
 * Add and remove event listeners for Ideogram's `ideogramDrawPathway` event
 *
 * This sets up the expression overlay for pathway nodes
 */
export function manageDrawPathway(studyAccession, cluster, annotation, ideogram) {
  const dotPlotParams = { studyAccession, cluster, annotation }
  if (annotation.type === 'group') {
    document.removeEventListener('ideogramDrawPathway')
    document.addEventListener('ideogramDrawPathway', event => {

      // Hide popover instantly upon drawing pathway; don't wait ~2 seconds
      document.querySelector('._ideogramTooltip').style.opacity = 0

      const details = event.detail
      const searchedGene = details.sourceGene
      const interactingGene = details.destGene
      renderPathwayExpression(
        searchedGene, interactingGene, ideogram,
        dotPlotParams
      )
    })
  }
}
