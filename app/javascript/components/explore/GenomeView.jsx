import React, { useEffect, useState } from 'react'
import igv from '@single-cell-portal/igv'
import _uniqueId from 'lodash/uniqueId'

import LoadingSpinner from '~/lib/LoadingSpinner'
import { log } from '~/lib/metrics-api'
import { fetchTrackInfo } from '~/lib/scp-api'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import { getReadOnlyToken, userHasTerraProfile } from '~/providers/UserProvider'
import { profileWarning } from '~/lib/study-overview/terra-profile-warning'

/** Component for displaying IGV for any BAM/BAI files provided with the study */
function GenomeView({ studyAccession, trackFileName, uniqueGenes, isVisible, exploreParams, updateExploreParams }) {
  const [isLoading, setIsLoading] = useState(false)
  const [trackFileList, setTrackFileList] = useState(null)
  const [igvInitializedFiles, setIgvInitializedFiles] = useState('')
  const [igvContainerId] = useState(_uniqueId('study-igv-'))
  const [showProfileWarning, setShowProfileWarning] = useState(false)

  const queriedGenes = exploreParams.genes

  useEffect(() => {
    // Get the track file names and urls from the server.
    setIsLoading(true)
    fetchTrackInfo(studyAccession).then(result => {
      setTrackFileList(result)
      setIsLoading(false)
    })
  }, [studyAccession])

  // create a concatenated string with the files to be rendered, so react can detect changes to it
  let fileListString = ''
  if (trackFileList) {
    fileListString = trackFileList.tracks.map(file => file.url).join(',')
  }

  // re-render IGV any time the listing of trackFiles changes
  useEffect(() => {
    if (trackFileList && trackFileList.tracks.length && isVisible) {
      // show profile warning from non-existent token due to incomplete Terra registration
      if (!userHasTerraProfile()) {
        setShowProfileWarning(true)
      }

      let listToShow = trackFileList.tracks
      if (trackFileName) {
        // if the user has specified a particular file name (likely because they are coming from the study download tab)
        // then limit the lsit of files to show to just that one
        listToShow = listToShow.filter(file => file.name === trackFileName)
      }
      const fileNamesToShow = listToShow.map(file => file.name).join(',')
      // we only want to render igv when this tab is visible (igv can't draw itself to hidden panels)
      // but we don't want to rerender every time the user toggles.
      // So we track what the last files are that we initialized
      // IGV with, and only rerender if they are different.
      if (igvInitializedFiles !== fileNamesToShow) {
        initializeIgv(igvContainerId, listToShow, trackFileList.gtfFiles, uniqueGenes, queriedGenes)
      }
      setIgvInitializedFiles(fileNamesToShow)
    }
  }, [fileListString, trackFileName, isVisible])

  // Search gene in IGV upon searching gene in Explore
  useEffect(() => {
    if (window.igvBrowser) {
      window.igvBrowser.search(queriedGenes[0])
    }
  }, [queriedGenes])

  /** handle clicks on the download 'browse in genome' buttons
   * This should get refactored when/if we migrate the other study-overview tabs to react
  */
  useEffect(() => {
    $(document).on('click', '.track-browse-genome', e => {
      $('#study-visualize-nav > a').click()
      const selectedTrack = $(e.target).attr('data-filename')
      updateExploreParams({ trackFileName: selectedTrack, tab: 'genome' })
    })
    $(document).on('click', '#study-visualize-nav > a', () => {
      // IGV doesn't handle rendering to hidden divs. So for edge cases where this renders but is not shown
      // (e.g. someone is viewing the genome tab, then navigates to summary tab, then reloads the page)
      // we trigger a resize event so that IGV will know to redraw itself
      if (isVisible) {
        window.dispatchEvent(new Event('resize'))
      }
    })
    return () => {
      $(document).off('click', '.track-browse-genome')
    }
  }, [])

  /** show the full list of files, rather than the specific selected one */
  function showAllFiles() {
    updateExploreParams({ trackFileName: '' })
  }

  return <div>
    { isLoading &&
      <LoadingSpinner testId="genome-view-loading-icon"/>
    }
    <div>
      <div id={igvContainerId}></div>
    </div>
    { trackFileName && trackFileList?.tracks?.length > 1 &&
      <a className="action" onClick={showAllFiles}>See all sequence files for this study</a>
    }
    { showProfileWarning && profileWarning }
  </div>
}

const SafeGenomeView = withErrorBoundary(GenomeView)
export default SafeGenomeView

/**
 * Get tracks for selected TSV (e.g. BAM, BED) files, to show genomic features
 */
function getTracks(tsvAndIndexFiles) {
  const tsvTracks = []

  for (let i = 0; i < tsvAndIndexFiles.length; i++) {
    const tsvTrack = tsvAndIndexFiles[i]

    tsvTrack.oauthToken = getReadOnlyToken()
    tsvTrack.label = tsvTrack.name
    tsvTrack.indexURL = tsvTrack.indexUrl

    tsvTracks.push(tsvTrack)
  }

  return tsvTracks
}

/**
 * Get tracks for selected BAM files, to show sequencing reads
 */
function getBamTracks(tracks) {
  let bam; let bamTrack; let i

  const bamTracks = []

  for (i = 0; i < tracks.length; i++) {
    bam = tracks[i]

    bamTrack = {
      url: bam.url,
      indexURL: bam.indexUrl,
      oauthToken: getReadOnlyToken(),
      label: bam.name
    }
    bamTracks.push(bamTrack)
  }

  return bamTracks
}

/**
 * Gets the track of genes and transcripts from the genome's BED file
 */
function getGenesTrack(gtfFiles, genome, genesTrackName) {
  // gtfFiles assigned in _genome.html.erb
  const gtfFile = gtfFiles[genome].genome_annotations

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
    oauthToken: getReadOnlyToken()
  }

  return genesTrack
}

/**
 * Instantiates and renders igv.js widget on the page
 */
async function initializeIgv(containerId, tracks, gtfFiles, uniqueGenes, queriedGenes) {
  // Bail if already displayed

  delete igv.browser

  const igvContainer = document.getElementById(containerId)
  igvContainer.innerHTML = ''

  let genomeId = tracks[0].genomeAssembly

  if (genomeId === 'GRCh38') {
    genomeId = 'hg38'
    gtfFiles[genomeId] = gtfFiles['GRCh38']
    delete gtfFiles['GRCh38']
  }

  let reference
  let searchOptions
  let fallbackLocus
  if (genomeId === 'Macaca_fascicularis_5.0') {
    fallbackLocus = 'chr1:1-2'

    // To consider:
    //  - Update genomes pipeline to make such files automatically reproducible
    const genomeAnnotationObj = tracks[0].genomeAnnotation
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
  let locus
  if (queriedGenes.length > 0) {
    // The user searched within a study for one or multiple genes
    locus = [queriedGenes[0]]
  } else if (uniqueGenes.length > 0) {
    // The user is viewing the default cluster plot, so find
    // a reasonable gene to view
    let defaultGeneIndex = uniqueGenes.indexOf('GAPDH')
    if (defaultGeneIndex === -1) {
      defaultGeneIndex = uniqueGenes.indexOf('Gapdh')
    }
    if (defaultGeneIndex === -1) {
      defaultGeneIndex = 0 // If GAPDH not found, use first gene in matrix
    }
    locus = [uniqueGenes[defaultGeneIndex]]
  } else {
    // Rarely, users will upload BAMs and *not* matrices.  This accounts for
    // that case.
    locus = [fallbackLocus]
  }

  const genesTrackName = `Genes | ${tracks[0].genomeAnnotation.name}`
  const genesTrack = getGenesTrack(gtfFiles, genomeId, genesTrackName)

  // const tsv = {
  //   url
  // }
  // const bedTrack = {
  //   url: tsv.url,
  //   indexURL: tsv.indexUrl,
  //   oauthToken: getReadOnlyToken(),
  //   label: tsv.name
  // }
  // const otherTracks = getTracks()


  const bedTrack = {
    url: 'https://www.googleapis.com/storage/v1/b/fc-5203332f-a200-4b9e-8a0e-1f2a892de5fb/o/pbmc_3k_atac_fragments.possorted.bed.gz?alt=media',
    indexUrl: 'https://www.googleapis.com/storage/v1/b/fc-5203332f-a200-4b9e-8a0e-1f2a892de5fb/o/pbmc_3k_atac_fragments.possorted.bed.gz.tbi?alt=media',
    name: 'pbmc_3k_atac_fragments.possorted.bed.gz',
    visibilityWindow: 100_000,
    height: 250,
    featureHeight: 7,
    expandedVGap: 1,
    displayMode: 'SQUISHED',
    colorBy: 'score',
    format: 'bed'
  }
  const otherTracks = getTracks([bedTrack])

  const bamTracks = getBamTracks(tracks)
  const trackList = [genesTrack].concat(otherTracks, bamTracks)

  // console.log('reference', reference)
  const igvOptions = { reference, locus, tracks: trackList }

  if (typeof searchOptions !== 'undefined') {
    igvOptions['search'] = searchOptions
  }

  window.igvBrowser = await igv.createBrowser(igvContainer, igvOptions)

  // Log igv.js initialization in Google Analytics
  ga('send', 'event', 'igv', 'initialize')
  log('igv:initialize')
}


// Monkey patch getKnownGenome to remove baked-in genes track.
// We use a different gene annotation source, in a different track order,
// so removing this default gives our genome browser instance a more
// polished feel.
const originalGetKnownGenomes = igv.GenomeUtils.getKnownGenomes
igv.GenomeUtils.getKnownGenomes = function() {
  return originalGetKnownGenomes.apply(this).then(reference => {
    const newRef = {}
    newRef['GRCm38'] = reference['mm10'] // Fix name
    Object.keys(reference).forEach(key => {
      delete reference[key].tracks
      newRef[key] = reference[key]
    })
    return newRef
  })
}
