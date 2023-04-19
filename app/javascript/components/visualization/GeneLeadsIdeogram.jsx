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
  // const annotFileName = 'gene_leads_All_Cells_UMAP--General_Celltype_v6.tsv'
  const annotFileName = 'gene_leads_All_Cells_UMAP--General_Celltype_v11.tsv'
  const filePath = `test%2F${annotFileName}`
  const annotationsPath = `${origin}/download/storage/v1/b/${bucket}/o/${filePath}?alt=media`

  window.fileIcon =
  `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-file-text" viewBox="0 0 16 16">
    <path d="M5 4a.5.5 0 0 0 0 1h6a.5.5 0 0 0 0-1H5zm-.5 2.5A.5.5 0 0 1 5 6h6a.5.5 0 0 1 0 1H5a.5.5 0 0 1-.5-.5zM5 8a.5.5 0 0 0 0 1h6a.5.5 0 0 0 0-1H5zm0 2a.5.5 0 0 0 0 1h3a.5.5 0 0 0 0-1H5z"/>
    <path d="M2 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2zm10-1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V2a1 1 0 0 0-1-1z"/>
  </svg>`

  window.deltaIcon =
  `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-triangle" viewBox="0 0 16 16">
  <path d="M7.938 2.016A.13.13 0 0 1 8.002 2a.13.13 0 0 1 .063.016.146.146 0 0 1 .054.057l6.857 11.667c.036.06.035.124.002.183a.163.163 0 0 1-.054.06.116.116 0 0 1-.066.017H1.146a.115.115 0 0 1-.066-.017.163.163 0 0 1-.054-.06.176.176 0 0 1 .002-.183L7.884 2.073a.147.147 0 0 1 .054-.057zm1.044-.45a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566z"/>
  </svg>`

  const colorMap = {
    'LC2': '#bb99ff', // '#999999',
    'LC1': '#9986a5', // '#f781bf',
    'neutrophils': '#d8a499', // '#66c2a5',
    'T cells': '#81a88d', // '#fc8d62',
    'eosinophils': '#d9d0d3', // '#984ea3',
    'dendritic cells': '#c6cdf7', // '#4daf4a',
    'GPMNB macrophages': '#ee46a6', // '#a65628',
    'CSN1S1 macrophages': '#e6a0c4',
    'fibroblasts': '#5eb668', // '#ff7f00'
    'B cells': '#7294d4'
  }

  /** Parse differential expression items, return as table for tooltip */
  function parseDE(items) {
    if (items.length < 1) {return ''}

    const rows = `<tbody><tr>${ items.map(item => {
      return (
      `<td>${item.group}</td>` +
      `<td>${item.log2fc}</td>` +
      `<td>${item.adjustedPval}</td>` +
      `<td>${item.scoresRank}</td>`
      )
    }).join('</tr><tr>') }</tr></tbody>`

    const head =
    '<thead><th>Group</th><th>log2(FC)</th><th>Adj. p-value</th><th>Rank in group</th></thead>'

    // const summary = 'summary="Differential expression"';
    const summary = '<div>Differential expression</div>'
    const style = 'style="border-collapse: collapse; margin: 0 auto;"'
    const styleBlock =
      `<style>
      ._ideogramTooltip th, ._ideogramTooltip td {
        text-align: left;
        padding: 2px 10px;
        border: 1px solid #DDD;
      }
      </style>`
    const result = `${styleBlock}${summary}<table ${style}>${head}${rows}</table>`

    return result
  }

  /**
     * Called immediately before displaying features along chromosomes
     */
  function onDrawAnnots() {
    const ideo = this

    const chrAnnots = ideo.annots

    for (let i = 0; i < chrAnnots.length; i++) {
      const annots = chrAnnots[i].annots

      for (let j = 0; j < annots.length; j++) {
        const annot = annots[j]

        if (ideo.config.colorMap && annot.differentialExpression?.length) {
          const colorMap = ideo.config.colorMap
          const group = annot.differentialExpression[0].group
          annot.color = colorMap[group]
          ideo.annots[i].annots[j] = annot
        }

        const differentialExpression = parseDE(annot.differentialExpression)
        const numMentions = annot.publicationMentions
        let publication = ''
        if (numMentions > 0) {
          publication = `${numMentions} mentions in publication<br/><br/>`
        }
        ideo.annotDescriptions.annots[annot.name].description =
          publication +
          differentialExpression
      }
    }
  }

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
      onDrawAnnots,
      geneLeadsDE: true,
      colorMap,
      // onPlotRelatedGenes,
      onWillShowAnnotTooltip,
      showGeneStructureInTooltip: true,
      showProteinInTooltip: true,
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
