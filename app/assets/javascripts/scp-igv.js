/* eslint-disable no-invalid-this */
/* eslint-disable guard-for-in */

/**
 * @fileoverview Functions and event handlers for igv.js genome browser.
 * Provides a way to view nucleotide sequencing reads in genomic context.
 */

// Persists 'Genome' tab and IGV embed across view states.
// Ensures that IGV doesn't disappear when user clicks 'Browse in genome' in
// default view, then searches a gene.
window.hasDisplayedIgv = false

const bamsToViewInIgv = []
const selectedBams = {}

/**
 * Upon clicking 'Browse in genome', show selected BAM in igv.js in Genome tab.
 */
$(document).on('click', '.bam-browse-genome', function(e) {
  let thisBam; let url; let i

  const selectedBam = $(this).attr('data-filename')

  // bamAndBaiFiles assigned in _genome.html.erb
  for (i = 0; i < bamAndBaiFiles.length; i++) {
    url = bamAndBaiFiles[i].url
    if (typeof url === 'undefined' || url === '?alt=media') {
      // Accounts for "Awaiting remote file"
      continue
    }
    thisBam = url.split('/o/')[1].split('?')[0]
    if (thisBam === selectedBam && selectedBam in selectedBams === false) {
      bamsToViewInIgv.push(bamAndBaiFiles[i])
    }
    selectedBams[thisBam] = 1
  }

  $('#study-visualize-nav > a').click()
  $('#genome-tab-nav > a').click()
})

$(document).on('click', '#genome-tab-nav', e => {
  const currentScroll = $(window).scrollTop()
  window.location.hash = '#genome-tab'
  window.scrollTo(0, currentScroll)
})

$(document).on('click', '#plots-tab-nav', e => {
  const currentScroll = $(window).scrollTop()
  window.location.hash = '#study-visualize'
  window.scrollTo(0, currentScroll)
})

/**
 * Get tracks for selected BAM files, to show sequencing reads
 */
function getBamTracks() {
  let bam; let bamTrack; let i; let bamFileName

  const bamTracks = []

  for (i = 0; i < bamAndBaiFiles.length; i++) {
    bam = bamAndBaiFiles[i]

    // Extracts BAM file name from its GCS API URL
    bamFileName = bam.url.split('/o/')[1].split('?')[0]

    bamTrack = {
      url: bam.url,
      indexURL: bam.indexUrl,
      oauthToken: window.accessToken,
      label: bamFileName
    }
    bamTracks.push(bamTrack)
  }

  return bamTracks
}

/**
 * Gets the track of genes and transcripts from the genome's BED file
 */
function getGenesTrack(genome, genesTrackName) {
  // gtfFiles assigned in _genome.html.erb
  const gtfFile = window.gtfFiles[genome].genome_annotations

  const genesTrack = {
    name: genesTrackName,
    url: `${gtfFile.url}?alt=media`,
    indexURL: `${gtfFile.indexUrl}?alt=media`,
    type: 'annotation',
    format: 'gtf',
    sourceType: 'file',
    height: 102,
    order: 0,
    visibilityWindow: 300000000,
    displayMode: 'EXPANDED',
    oauthToken: window.accessToken // Assigned in _genome.html.erb
  }

  return genesTrack
}

// Monkey patch getKnownGenome to remove baked-in genes track.
// We use a different gene annotation source, in a different track order,
// so removing this default gives our genome browser instance a more
// polished feel.
const originalGetKnownGenomes = igv.GenomeUtils.getKnownGenomes
igv.GenomeUtils.getKnownGenomes = function() {
  return originalGetKnownGenomes.apply(this).then(reference => {
    let key
    const newRef = {}
    newRef['GRCm38'] = reference['mm10'] // Fix name
    for (key in reference) {
      delete reference[key].tracks
      newRef[key] = reference[key]
    }
    return newRef
  })
}

function igvIsDisplayed() {
  return $('.igv-root-div').length > 0
}

/**
 * Instantiates and renders igv.js widget on the page
 */
function initializeIgv() {
  // Bail if already displayed
  if (igvIsDisplayed()) return

  delete igv.browser

  if (bamsToViewInIgv.includes(bamAndBaiFiles[0]) === false) {
    bamsToViewInIgv.push(bamAndBaiFiles[0])
  }

  const igvContainer = document.getElementById('igv-container')

  const genomeId = bamsToViewInIgv[0].genomeAssembly

  let reference
  let searchOptions
  let fallbackLocus
  if (genomeId === 'Macaca_fascicularis_5.0') {
    fallbackLocus = 'chr1:1-2'

    // To consider:
    //  - Update genomes pipeline to make such files automatically reproducible
    const genomeAnnotationObj = bamsToViewInIgv[0].genomeAnnotation
    const genomePath =
      `${genomeAnnotationObj.link.split('/').slice(0, -2).join('%2F')}%2F`
    const bucket = genomeAnnotationObj.bucket_id
    const gcsBase = 'https://www.googleapis.com/storage/v1/b/'
    const macacaFascicularisBase = `${gcsBase + bucket}/o/${genomePath}`

    const fasta = 'Macaca_fascicularis.Macaca_fascicularis_5.0.dna.toplevel.fa'
    const cytoband = 'macaca-fascicularis-cytobands.txt'

    searchOptions = {
      url: 'https://rest.ensembl.org/lookup/symbol/macaca_fascicularis/$FEATURE$?content-type=application/json',
      chromosomeField: 'seq_region_name',
      displayName: 'display_name'
    }

    reference = {
      id: genomeId,
      cytobandURL: `${macacaFascicularisBase}${cytoband}?alt=media`,
      fastaURL: `${macacaFascicularisBase}${fasta}?alt=media`,
      indexURL: `${macacaFascicularisBase}${fasta}.fai?alt=media`,
      headers: {
        'Authorization': `Bearer ${window.accessToken}`
      }
    }
  } else {
    fallbackLocus = 'myc'
    reference = genomeId
  }
  const queriedGenes = $('.queried-gene')
  let locus
  if (queriedGenes.length > 0) {
    // The user searched within a study for one or multiple genes
    locus = [queriedGenes.first().text()]
  } else if (window.uniqueGenes.length > 0) {
    // The user is viewing the default cluster plot, so select
    // their first in their matrix
    locus = [window.uniqueGenes[0]]
  } else {
    // Rarely, users will upload BAMs and *not* matrices.  This accounts for
    // that case.
    locus = [fallbackLocus]
  }

  const genesTrackName = `Genes | ${bamsToViewInIgv[0].genomeAnnotation.name}`
  const genesTrack = getGenesTrack(genomeId, genesTrackName)
  const bamTracks = getBamTracks()
  const tracks = [genesTrack].concat(bamTracks)

  const igvOptions = { reference, locus, tracks }

  if (typeof searchOptions !== 'undefined') {
    igvOptions['search'] = searchOptions
  }

  igv.createBrowser(igvContainer, igvOptions)


  // Log igv.js initialization in Google Analytics
  ga('send', 'event', 'igv', 'initialize')
  window.SCP.log('igv:initialize')
}

$(document).on('click', '#genome-tab-nav > a', event => {
  if (typeof bamAndBaiFiles !== 'undefined') {
    initializeIgv()
  }
})

$(document).ready(() => {
  // Bail if on a page without genome visualization support
  if (typeof accessToken === 'undefined') return

  if (window.location.hash === '#genome-tab') {
    $('#study-visualize-nav > a').click()

    // Reload igv if refreshing
    $('#genome-tab-nav > a').click()
  }
})
