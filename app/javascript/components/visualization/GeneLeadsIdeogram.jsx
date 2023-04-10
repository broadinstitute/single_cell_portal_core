/**
 * @fileoverview Ideogram for gene leads: features to consider searching
 *
 * This code primes gene search in the Study Overview page.  It is
 * called before searching for a gene, invoking functionality in Ideogram.js to
 * retrieve and plot interesting genes across the genome.  Users can then click a
 * gene to trigger a search on that gene.  The intent is to improve
 * discoverability for genes of biological interest.
 *
 * TODO (pre-GA):
 * - Consolidate redundant code between RelatedGenesIdeogram and GeneLeadsIdeogram
 * - Refine analytics for related genes and gene leads ideograms
 * - Expose gene leads API via Ideogram.js so SCP UI can handle color, etc.
 * - Refine Ideogram width handling to account for viewport resizing
 */

import React, { useEffect } from 'react'
import Ideogram from 'ideogram'

import PlotUtils from '~/lib/plot'
const ideogramHeight = PlotUtils.ideogramHeight
import { log } from '~/lib/metrics-api'
import { logStudyGeneSearch } from '~/lib/search-metrics'

/** Handle clicks on Ideogram annotations */
function onClickAnnot(annot) {
  // Ideogram object; used to inspect ideogram state
   const ideogram = this // eslint-disable-line

  // Enable merge of related-genes log props into search log props
  // This helps profile the numerator of click-through-rate
  const otherProps = {}
  // const props = getRelatedGenesAnalytics(ideogram)
  // Object.entries(props).forEach(([key, value]) => {
  //   otherProps[`geneHints:${key}`] = value
  // })

  const trigger = 'click-gene-leads'
  const speciesList = ideogram.SCP.speciesList
  logStudyGeneSearch([annot.name], trigger, speciesList, otherProps)
  ideogram.SCP.searchGenes([annot.name])
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
 function showGeneLeadsIdeogram(target) { // eslint-disable-line

  if (!window.ideogram) {return}

  const ideoContainer =
     document.querySelector('#gene-leads-ideogram-container')

  if (!genomeHasChromosomes()) {
    ideoContainer.classList = 'hidden-gene-leads-ideogram'
    ideoContainer.innerHTML = ''
    return
  }

  putIdeogramInPlotTabs(ideoContainer, target)

  // Make Ideogram visible
  ideoContainer.classList = 'show-gene-leads-ideogram'
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
  let props = {} // let props = ideogram.getTooltipAnalytics(annot)

  // `props` is null if it is merely analytics noise.
  // Accounts for quick moves from label to annot, or away then immediately
  // back to same annot.  Such action flickers tooltip and represents a
  // technical artifact that is not worth analyzing.
  if (props) {
    props = conformAnalytics(props, ideogram)
    log('ideogram:gene-leads:tooltip', props)
  }

  return annot
}

/** Get summary of related-genes ideogram that was just loaded or clicked */
function getRelatedGenesAnalytics(ideogram) {
  let props = Object.assign({}, ideogram.relatedGenesAnalytics)
  props = conformAnalytics(props, ideogram)
  return props
}

// /**
//   * Callback to report analytics to Mixpanel.
//   * Helps profile denominator of click-through-rate
//   */
// function onPlotRelatedGenes() {
//   // Ideogram object; used to inspect ideogram state
//    const ideogram = this // eslint-disable-line
//   const props = getRelatedGenesAnalytics(ideogram)

//   log('ideogram:gene-leads', props)
// }


/**
  * Initiates Ideogram for related genes
  *
  * This is only done in the context of single-gene search in Study Overview
  */
export default function RelatedGenesIdeogram({
  gene, taxon, target, genesInScope, searchGenes, speciesList
}) {
  if (taxon === null) {
    // Quick fix to decrease Sentry error log rate
    // TODO (SCP-4360): Address this more robustly a bit upstream, then remove this patch
    return null
  }

  const verticalPad = 40 // Total top and bottom padding

  const origin = 'https://storage.googleapis.com'
  const bucket = 'broad-singlecellportal-public'

  // TODO (pre-GA): Decide file path; parameterize clustering, annotation
  const annotFileName = 'gene_leads_All_Cells_UMAP--General_Celltype_v5.tsv'
  const filePath = `test%2F${annotFileName}`
  const annotationsPath = `${origin}/download/storage/v1/b/${bucket}/o/${filePath}?alt=media`

  useEffect(() => {
    const ideoConfig = {
      container: '#gene-leads-ideogram-container',
      organism: taxon,
      chrWidth: 9,
      legendName: 'Gene leads',
      chrMargin: -4,
      chrHeight: ideogramHeight - verticalPad,
      chrLabelSize: 12,
      annotationHeight: 7,
      annotationsPath,
      onClickAnnot,
      // onPlotRelatedGenes,
      onWillShowAnnotTooltip,
      showGeneStructureInTooltip: false,
      showParalogNeighborhoods: taxon === 'Homo sapiens', // Workaround Ideogram bug, remove upon upstream fix
      onLoad() {
        // Handles edge case: when organism lacks chromosome-level assembly
        if (!genomeHasChromosomes()) {return}
        // this.plotRelatedGenes(gene)
        showGeneLeadsIdeogram(target)
      }
    }
    window.ideogram =
       Ideogram.initGeneLeads(ideoConfig, genesInScope)

    // Extend ideogram with custom SCP function to search genes
    window.ideogram.SCP = { searchGenes, speciesList }
  }, [gene])

  return (
    <div
      id="gene-leads-ideogram-container"
      className="hidden-related-genes-ideogram">
    </div>
  )
}
