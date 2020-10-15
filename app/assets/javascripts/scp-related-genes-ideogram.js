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

/** Handle clicks on Ideogram annotations */
function onClickAnnot(annot) {
  // Ideogram object; used to inspect ideogram state
  const ideogram = this // eslint-disable-line
  document.querySelector('#search_genes').value = annot.name

  setFoundRelatedGenes(false)

  // Enable merge of related-genes log props into search log props
  // This helps profile the numerator of click-through-rate
  const event = {}
  const props = getRelatedGenesAnalytics(ideogram)
  Object.entries(props).forEach(([key, value]) => {
    event[`relatedGenes:${key}`] = value
  })

  event['type'] = 'click-related-genes'

  window.submitGeneSearch(event)
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
function putIdeogramInPlotTabs(ideoContainer) {
  const tabContent = document.querySelector('#render-target .tab-content')
  const ideoOuter = document.querySelector('#_ideogramOuterWrap')
  const chrHeight = `${window.ideogram.config.chrHeight}px`

  // Ideogram has `position: absolute`, so manual top offsets are needed
  ideoOuter.style.height = chrHeight

  tabContent.prepend(ideoContainer)
}

/**
 * Displays Ideogram after getting gene search results in Study Overview
 */
function showRelatedGenesIdeogram() { // eslint-disable-line

  if (!window.ideogram) return

  const ideoContainer =
    document.querySelector('#related-genes-ideogram-container')

  if (!genomeHasChromosomes()) {
    ideoContainer.classList = 'hidden-related-genes-ideogram'
    ideoContainer.innerHTML = ''
    return
  }

  putIdeogramInPlotTabs(ideoContainer)
}

/**
 * Get summary of related-genes ideogram that was just loaded or clicked
 */
function getRelatedGenesAnalytics(ideogram) {
  const props = Object.assign({}, ideogram.relatedGenesAnalytics)

  // Use DSP-conventional name
  props['perfTime'] = props.time
  delete props['time']

  props['species'] = ideogram.getScientificName(ideogram.config.taxid)

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

  window.SCP.log('ideogram:related-genes', props)
}

/**
 * Set inner visibility of ideogram
 *
 * @param found Boolean Whether related genes have been found
 */
function setFoundRelatedGenes(found) {
  const innerFoundClass = (found) ? 'found-related-genes' : ''
  const innerSelect = '#related-genes-ideogram-container #_ideogramInnerWrap'
  document.querySelector(innerSelect).classList = innerFoundClass

  if (found) {
    const ideoContainer =
      document.querySelector('#related-genes-ideogram-container')

    // Make Ideogram visible
    ideoContainer.classList = 'show-related-genes-ideogram'
  }
}

/**
 * Show ideogram upon finding any interacting gene or paralog
 *
 * This enables ideogram to only be shown when related genes are found (while
 * also allowing incremental rendering).
 */
function onFindRelatedGenes() {
  setFoundRelatedGenes(true)
}

/**
 * Initiates Ideogram for related genes
 *
 * This is only done in the context of single-gene search in Study Overview
 */
function createRelatedGenesIdeogram(taxon) { // eslint-disable-line

  if (taxon === null) return

  // Clear any prior ideogram
  if (typeof window.ideogram !== 'undefined') {
    delete window.ideogram
    const ideoContainer =
      document.querySelector('#related-genes-ideogram-container')
    if (ideoContainer) ideoContainer.remove()
  }

  const gene = document.querySelector('#search_genes').value.trim()

  // Create scaffolding for Ideogram for related genes
  const ideoContainer =
    '<div id="related-genes-ideogram-container" class="hidden-related-genes-ideogram"></div>' // eslint-disable-line
  document.querySelector('body').insertAdjacentHTML('beforeEnd', ideoContainer)

  const ideoConfig = {
    container: '#related-genes-ideogram-container',
    organism: taxon,
    chrWidth: 9,
    chrHeight: 100,
    chrLabelSize: 12,
    annotationHeight: 7,
    onClickAnnot,
    onPlotRelatedGenes,
    onFindRelatedGenes,
    onLoad() {
      // Handles edge case: when organism lacks chromosome-level assembly
      if (!genomeHasChromosomes()) return
      this.plotRelatedGenes(gene)
    }
  }

  window.ideogram =
    Ideogram.initRelatedGenes(ideoConfig, window.SCP.uniqueGenes)
}
