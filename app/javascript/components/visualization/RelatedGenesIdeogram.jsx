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
import { manageDrawPathway } from '~/lib/pathway-expression'

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
  ideogram.SCP.queryFn([annot.name])
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
function onWillShowAnnotTooltip(annot, param2, param3) {
  if (annot instanceof Promise) {
    return null
  }

  // Ideogram object; used to inspect ideogram state
  const ideogram = this // eslint-disable-line
  const resolvedAnnot = annot

  console.log('resolvedAnnot', resolvedAnnot)
  let props = window.ideogram.getTooltipAnalytics(annot)

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
  if (!ideoTissueToggle) {return} // Some genes (e.g. CSN2) have <= 3 tissue entries
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
  gene, taxon, target, genesInScope, queryFn, speciesList,
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
      showVariantInTooltip: false,
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

    manageDrawPathway(studyAccession, cluster, annotation, ideogram)

    // Extend ideogram with custom SCP function to search genes
    window.ideogram.SCP = { queryFn, speciesList }
  }, [gene])

  useEffect(() => {
    manageDrawPathway(studyAccession, cluster, annotation, window.ideogram)
  }, [cluster, annotation])

  return (
    <div
      id="related-genes-ideogram-container"
      className="hidden-related-genes-ideogram">
    </div>
  )
}
