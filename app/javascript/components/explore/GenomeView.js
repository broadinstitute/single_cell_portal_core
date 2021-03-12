import React, { useEffect, useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'
import igv from '@single-cell-portal/igv'
import _uniqueId from 'lodash/uniqueId'

import { fetchBamFileInfo } from 'lib/scp-api'
import { withErrorBoundary } from 'lib/ErrorBoundary'

/** Component for displaying IGV for any bam/bai files provided with the study */
function GenomeView({ studyAccession, bamFileName, isVisible, updateExploreParams }) {
  const [isLoading, setIsLoading] = useState(false)
  const [bamFileList, setBamFileList] = useState(null)
  const [igvInitializedFiles, setIgvInitializedFiles] = useState('')
  const [igvContainerId] = useState(_uniqueId('study-igv-'))

  useEffect(() => {
    // go get the bam file anmes and urls from the server.
    setIsLoading(true)
    fetchBamFileInfo(studyAccession).then(result => {
      setBamFileList(result)
      setIsLoading(false)
    })
  }, [studyAccession])

  // create a concatenated string with the files to be rendered, so react can detect changes to it
  let fileListString = ''
  if (bamFileList) {
    fileListString = bamFileList.bamAndBaiFiles.map(file => file.url).join(',')
  }

  // re-render IGV any time the listing of bamFiles changes
  useEffect(() => {
    if (bamFileList && bamFileList.bamAndBaiFiles.length && isVisible) {
      let listToShow = bamFileList.bamAndBaiFiles
      if (bamFileName) {
        // if the user has specified a particular file name (likely because they are coming from the study download tab)
        // then limit the lsit of files to show to just that one
        listToShow = listToShow.filter(file => file.name === bamFileName)
      }
      const fileNamesToShow = listToShow.map(file => file.name).join(',')
      // we only want to render igv when this tab is visible (igv can't draw itself to hidden panels)
      // but we don't want to rerender every time the user toggles.
      // So we track what the last files are that we initialized
      // IGV with, and only rerender if they are different.
      if (igvInitializedFiles !== fileNamesToShow) {
        initializeIgv(igvContainerId, listToShow, bamFileList.gtfFiles)
      }
      setIgvInitializedFiles(fileNamesToShow)
    }
  }, [fileListString, bamFileName, isVisible])

  /** handle clicks on the download 'browse in genome' buttons
   * This should get refactored when/if we migrate the other study-overview tabs to react
  */
  useEffect(() => {
    $(document).on('click', '.bam-browse-genome', e => {
      $('#study-visualize-nav > a').click()
      const selectedBam = $(e.target).attr('data-filename')
      updateExploreParams({ bamFileName: selectedBam, tab: 'genome' })
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
      $(document).off('click', '.bam-browse-genome')
    }
  }, [])

  /** show the full list of files, rather than the specific selected one */
  function showAllFiles() {
    updateExploreParams({ bamFileName: '' })
  }

  return <div>
    { isLoading &&
      <FontAwesomeIcon
        icon={faDna}
        data-testid="genome-view-loading-icon"
        className="gene-load-spinner"
      />
    }
    <div>
      <div id={igvContainerId}></div>
    </div>
    { bamFileName && bamFileList?.bamAndBaiFiles?.length > 1 &&
      <a className="action" onClick={showAllFiles}>See all sequence files for this study</a>
    }
  </div>
}

const SafeGenomeView = withErrorBoundary(GenomeView)
export default SafeGenomeView


/**
 * Get tracks for selected BAM files, to show sequencing reads
 */
function getBamTracks(bamAndBaiFiles) {
  let bam; let bamTrack; let i;

  const bamTracks = []

  for (i = 0; i < bamAndBaiFiles.length; i++) {
    bam = bamAndBaiFiles[i]

    bamTrack = {
      url: bam.url,
      indexURL: bam.indexUrl,
      oauthToken: window.accessToken,
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
    oauthToken: window.accessToken // Assigned in _genome.html.erb
  }

  return genesTrack
}

/**
 * Instantiates and renders igv.js widget on the page
 */
function initializeIgv(containerId, bamAndBaiFiles, gtfFiles) {
  // Bail if already displayed

  delete igv.browser

  const igvContainer = document.getElementById(containerId)
  igvContainer.innerHTML = ''

  const genomeId = bamAndBaiFiles[0].genomeAssembly

  let reference
  let searchOptions
  let fallbackLocus
  if (genomeId === 'Macaca_fascicularis_5.0') {
    fallbackLocus = 'chr1:1-2'

    // To consider:
    //  - Update genomes pipeline to make such files automatically reproducible
    const genomeAnnotationObj = bamAndBaiFiles[0].genomeAnnotation
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
  } else if (window.SCP.uniqueGenes.length > 0) {
    // The user is viewing the default cluster plot, so select
    // their first in their matrix
    locus = [window.SCP.uniqueGenes[0]]
  } else {
    // Rarely, users will upload BAMs and *not* matrices.  This accounts for
    // that case.
    locus = [fallbackLocus]
  }

  const genesTrackName = `Genes | ${bamAndBaiFiles[0].genomeAnnotation.name}`
  const genesTrack = getGenesTrack(gtfFiles, genomeId, genesTrackName)
  const bamTracks = getBamTracks(bamAndBaiFiles)
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
