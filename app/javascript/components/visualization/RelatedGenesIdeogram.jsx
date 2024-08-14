/**
 * @fileoverview Ideogram for related genes
 *
 * This code enhances single-gene search in the Study Overview page.  It is
 * called upon searching for a gene, invoking functionality in Ideogram.js to
 * retrieve and plot related genes across the genome.  Users can then click a
 * related gene to trigger a search on that gene.  The intent is to improve
 * discoverability for genes of biological interest.
 *
 * More context, a screenshot, and architecture diagram are available at:
 * https://github.com/broadinstitute/single_cell_portal_core/pull/735
 */

import React, { useEffect } from 'react'
import Ideogram from 'ideogram'

import PlotUtils from '~/lib/plot'
const ideogramHeight = PlotUtils.ideogramHeight
import { log } from '~/lib/metrics-api'
import { logStudyGeneSearch } from '~/lib/search-metrics'
import { renderBackgroundDotPlot, getDotPlotMetrics } from './DotPlot'
import { getAnnotationValues } from '~/lib/cluster-utils'

/** Handle clicks on Ideogram annotations */
function onClickAnnot(annot) {
  // Ideogram object; used to inspect ideogram state
  const ideogram = this // eslint-disable-line

  // Enable merge of related-genes log props into search log props
  // This helps profile the numerator of click-through-rate
  const otherProps = {}
  const props = getRelatedGenesAnalytics(ideogram)
  Object.entries(props).forEach(([key, value]) => {
    otherProps[`relatedGenes:${key}`] = value
  })

  const trigger = 'click-related-genes'
  const speciesList = ideogram.SCP.speciesList
  logStudyGeneSearch([annot.name], trigger, speciesList, otherProps)
  ideogram.SCP.searchGenes([annot.name])
}

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

  /** After invisible dot plot renders, color each gene by expression metrics */
  function backgroundDotPlotDrawCallback(dotPlot) {
    // The first render is for uncollapsed cell-x-gene metrics (heatmap),
    // the second render is for collapsed label-x-gene metrics (dotplot)
    numDraws += 1
    if (numDraws === 1) {return}

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
 * Reports if current genome assembly has chromosome length data
 *
 * Enables handling for taxons that cannot be visualized in an ideogram.
 * Example edge case: axolotl study SCP499.
 */
function genomeHasChromosomes() {
  return window.ideogram.chromosomesArray.length > 0
}

/**
* Move Ideogram within expression plot tabs, per UX recommendation
*/
function putIdeogramInPlotTabs(ideoContainer, target) {
  const tabContent = document.querySelector(target)
  const ideoOuter = document.querySelector('#_ideogramOuterWrap')
  const chrHeight = `${window.ideogram.config.chrHeight}px`

  // Ideogram has `position: absolute`, so manual top offsets are needed
  ideoOuter.style.height = chrHeight

  tabContent.prepend(ideoContainer)
}

/**
 * Displays Ideogram after getting gene search results in Study Overview
 */
function showRelatedGenesIdeogram(target) { // eslint-disable-line

  if (!window.ideogram) {return}

  const ideoContainer =
    document.querySelector('#related-genes-ideogram-container')

  if (!genomeHasChromosomes()) {
    ideoContainer.classList = 'hidden-related-genes-ideogram'
    ideoContainer.innerHTML = ''
    return
  }

  putIdeogramInPlotTabs(ideoContainer, target)

  // Make Ideogram visible
  ideoContainer.classList = 'show-related-genes-ideogram'
}

/** Refine analytics to use DSP-conventional names */
function conformAnalytics(props, ideogram) {
  // Use DSP-conventional name
  props['perfTime'] = props.timeTotal
  delete props.timeTotal

  props['species'] = ideogram.organismScientificName

  return props
}

/** Log hover over related genes ideogram tooltip */
function onWillShowAnnotTooltip(annot) {
  // Ideogram object; used to inspect ideogram state
  const ideogram = this // eslint-disable-line
  let props = ideogram.getTooltipAnalytics(annot)

  // `props` is null if it is merely analytics noise.
  // Accounts for quick moves from label to annot, or away then immediately
  // back to same annot.  Such action flickers tooltip and represents a
  // technical artifact that is not worth analyzing.
  if (props) {
    props = conformAnalytics(props, ideogram)
    log('ideogram:related-genes:tooltip', props)
  }

  return annot
}

/** Persist click handling for tissue toggle click */
function addTissueToggleClickHandler(newTitle) {
  const ideoTissueToggle = document.querySelector('._ideoMoreOrLessTissue')
  ideoTissueToggle.addEventListener('click', () => {
    const ideoTissuePlotTitle = document.querySelector('._ideoTissuePlotTitle')
    ideoTissuePlotTitle.innerHTML = newTitle
    addTissueToggleClickHandler(newTitle)
  })
}

/** Make updates (e.g. to the tooltip) after showing tooltip */
function onDidShowAnnotTooltip() {
  const ideoTissuePlotTitle = document.querySelector('._ideoTissuePlotTitle')
  if (!ideoTissuePlotTitle) {return}
  const hoveredGene = document.querySelector('#ideo-related-gene').innerText
  const gtexUrl = `https://www.gtexportal.org/home/gene/${hoveredGene}`
  const gtexLink = `<a href="${gtexUrl}" class="_ideoTitleGtexLink" target="blank">GTEx</a>`
  const newTitle = `Reference expression by tissue, per ${gtexLink}`
  ideoTissuePlotTitle.innerHTML = newTitle

  addTissueToggleClickHandler(newTitle)
}

/** Get summary of related-genes ideogram that was just loaded or clicked */
function getRelatedGenesAnalytics(ideogram) {
  let props = Object.assign({}, ideogram.relatedGenesAnalytics)
  props = conformAnalytics(props, ideogram)
  return props
}

/**
 * Callback to report analytics to Mixpanel.
 * Helps profile denominator of click-through-rate
 */
function onPlotRelatedGenes() {
  // Ideogram object; used to inspect ideogram state
  const ideogram = this // eslint-disable-line
  const props = getRelatedGenesAnalytics(ideogram)

  log('ideogram:related-genes', props)
}

/**
 * Initiates Ideogram for related genes
 *
 * This is only done in the context of single-gene search in Study Overview
 */
export default function RelatedGenesIdeogram({
  gene, taxon, target, genesInScope, searchGenes, speciesList,
  studyAccession, cluster, annotation
}) {
  if (taxon === null) {
    // Quick fix to decrease Sentry error log rate
    // TODO (SCP-4360): Address this more robustly a bit upstream, then remove this patch
    return null
  }

  const verticalPad = 40 // Total top and bottom padding

  // For Ideogram functionality only available for human and mouse
  const showAdvanced = ['Homo sapiens', 'Mus musculus'].includes(taxon)

  useEffect(() => {
    const ideoConfig = {
      container: '#related-genes-ideogram-container',
      organism: taxon,
      chrWidth: 9,
      chrHeight: ideogramHeight - verticalPad,
      chrLabelSize: 12,
      annotationHeight: 7,
      onClickAnnot,
      onPlotRelatedGenes,
      onWillShowAnnotTooltip,
      onDidShowAnnotTooltip,
      showGeneStructureInTooltip: showAdvanced,
      showProteinInTooltip: showAdvanced,
      showParalogNeighborhoods: showAdvanced,
      onLoad() {
        // Handles edge case: when organism lacks chromosome-level assembly
        if (!genomeHasChromosomes()) {return}
        this.plotRelatedGenes(gene)
        showRelatedGenesIdeogram(target)
      }
    }
    const ideogram = Ideogram.initRelatedGenes(ideoConfig, genesInScope)
    window.ideogram = ideogram

    const dotPlotParams = { studyAccession, cluster, annotation }
    if (annotation.type === 'group') {
      document.removeEventListener('ideogramDrawPathway')
      document.addEventListener('ideogramDrawPathway', event => {
        const details = event.detail
        const searchedGene = details.sourceGene
        const interactingGene = details.destGene
        renderPathwayExpression(
          searchedGene, interactingGene, ideogram,
          dotPlotParams
        )
      })
    }

    // Extend ideogram with custom SCP function to search genes
    window.ideogram.SCP = { searchGenes, speciesList }
  }, [gene])

  return (
    <div
      id="related-genes-ideogram-container"
      className="hidden-related-genes-ideogram">
    </div>
  )
}
