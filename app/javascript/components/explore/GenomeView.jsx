import React, { useEffect, useState } from 'react'
import igv from '@single-cell-portal/igv'
import _uniqueId from 'lodash/uniqueId'

import LoadingSpinner from '~/lib/LoadingSpinner'
import { log } from '~/lib/metrics-api'
import { fetchTrackInfo } from '~/lib/scp-api'
import { updateTrack } from '~/lib/igv-utils'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import { getReadOnlyToken, userHasTerraProfile } from '~/providers/UserProvider'
import { profileWarning } from '~/lib/study-overview/terra-profile-warning'

/** Component for displaying IGV for any BAM/BAI files provided with the study */
function GenomeView({
  studyAccession, trackFileName, uniqueGenes, isVisible, cellFilteringSelection,
  queriedGenes, updateExploreParams
}) {
  const [isLoading, setIsLoading] = useState(false)

  let numFacets
  if (cellFilteringSelection) {
    numFacets = Object.keys(cellFilteringSelection).length
  }
  const [isLoadingFilters, setIsLoadingFilters] = useState(cellFilteringSelection && numFacets > 0)
  const [trackFileList, setTrackFileList] = useState(null)
  const [igvInitializedFiles, setIgvInitializedFiles] = useState('')
  const [igvContainerId] = useState(_uniqueId('study-igv-'))
  const [showProfileWarning, setShowProfileWarning] = useState(false)

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
        // then limit the list of files to show to just that one
        listToShow = listToShow.filter(file => file.name === trackFileName)
      }
      const fileNamesToShow = listToShow.map(file => file.name).join(',')
      // we only want to render igv when this tab is visible (igv can't draw itself to hidden panels)
      // but we don't want to rerender every time the user toggles.
      // So we track what the last files are that we initialized
      // IGV with, and only rerender if they are different.
      if (igvInitializedFiles !== fileNamesToShow) {
        initializeIgv(
          igvContainerId, listToShow, trackFileList.gtfFiles, uniqueGenes,
          queriedGenes, cellFilteringSelection, isLoadingFilters, setIsLoadingFilters
        )
      }
      setIgvInitializedFiles(fileNamesToShow)
    }
  }, [fileListString, trackFileName, isVisible])

  /** Wrap igvBrowser.search, retryably */
  function igvSearch(queriedGenes, retryAttempt=0) {
    if (window.igvBrowser) {
      // Retry search every .25 s, up to ~5 s, if needed track absent
      if (!trackFileList && retryAttempt < 20) {
        setTimeout(() => {
          igvSearch(queriedGenes, retryAttempt++)
        }, 250)
      } else {
        const genomeId = trackFileList.tracks[0].genomeAssembly
        getDefaultLocus(queriedGenes, uniqueGenes, genomeId)
        window.igvBrowser.search(queriedGenes[0])

        const filteredCellNames = window.SCP.filteredCellNames
        if (filteredCellNames) {
          filterIgvFeatures(filteredCellNames)
        }
      }
    }
  }

  // Search gene in IGV upon searching gene in Explore
  useEffect(() => {
    igvSearch(queriedGenes)
  }, [queriedGenes.join(',')])

  /** handle clicks on the download 'browse in genome' buttons
   * This should get refactored when/if we migrate the other study-overview tabs to react
  */
  useEffect(() => {
    if (window.$) {
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
      <div id={igvContainerId} style={{ marginBottom: '20px' }}></div>
    </div>
    { trackFileName && trackFileList?.tracks?.length > 1 &&
      <a className="action" onClick={showAllFiles}>See all sequence files for this study</a>
    }
    { showProfileWarning && profileWarning }
  </div>
}

const SafeGenomeView = withErrorBoundary(GenomeView)
export default SafeGenomeView

/** Get unfiltered genomic features on current chromosome */
function getOriginalChrFeatures(trackIndex, igvBrowser) {
  const chr = igvBrowser.referenceFrameList[0].chr

  if (
    typeof window.originalFeatures === 'undefined' ||
    chr in window.originalFeatures === false
  ) {
    if (igvBrowser.trackViews[trackIndex].track.featureSource.featureCache) {
      window.originalFeatures = igvBrowser.trackViews[trackIndex].track.featureSource.featureCache.allFeatures
    } else {
      return
    }
  }

  const originalChrFeatures = window.originalFeatures[chr]

  return originalChrFeatures
}

/** Determine if feature is in genomic frame */
function getIsFeatureInFrame(feature, igvBrowser) {
  const frame = igvBrowser.referenceFrameList[0]

  const isFeatureInFrame = (
    // Contained:
    // Frame:     --------
    // Feature:     ----
    (feature.start >= frame.start && feature.end <= frame.end) ||

    // Overlaps start
    // Frame:     --------
    // Feature:  ----
    (feature.start <= frame.start && feature.end >= frame.start) ||

    // Overlaps end
    // Frame:     --------
    // Feature:         ----
    (feature.start <= frame.end && feature.end >= frame.end) ||

    // Spans
    // Frame:     --------
    // Feature: ------------
    (feature.start <= frame.start && feature.end >= frame.end)
  )

  return isFeatureInFrame
}

// /**
//    * TODO: Consider maturing this filtering by "score", which is a
//    * dimension that is _not_ an annotation yet is still often applicable
//    * for all genomic features in a BED file.
//    *
//    * Context, demo:
//    * https://github.com/broadinstitute/single_cell_portal_core/pull/2021
//    */
// function filterByScore(scoreSelection) {
//   const trackIndex = 4 // Track index
//   const igvBrowser = window.igvBrowser

//   const originalChrFeatures = getOriginalChrFeatures(trackIndex, igvBrowser)

//   if (!scoreSelection) {
//     scoreSelection = new Set(2)
//   }
//   // const inputs = document.querySelectorAll('.filters input')
//   // inputs.forEach(input => {
//   //   if (input.checked) {
//   //     selection[input.value] = 1
//   //   }
//   // })

//   const filteredFeatures = originalChrFeatures.filter(feature => scoreSelection.has(feature.score))

//   updateTrack(trackIndex, filteredFeatures, igv, igvBrowser)
// }

/** Filter genomic features */
export function filterIgvFeatures(filteredCellNames, retryAttempt=0) {
  const igvBrowser = window.igvBrowser
  if (!igvBrowser?.tracks) {return}
  const trackIndex = igvBrowser.tracks.findIndex(
    track => track.config?.dataType === 'atac-fragment'
  )

  const originalChrFeatures = getOriginalChrFeatures(trackIndex, igvBrowser)

  if (typeof originalChrFeatures === 'undefined') {
    if (retryAttempt < 20) { // Poll RAM every 250 ms, up to 20 times (~5 s)
      setTimeout(() => {
        filterIgvFeatures(filteredCellNames, retryAttempt++)
      }, 250)
    }
    return
  }
  const filteredFeatures = originalChrFeatures.filter(
    feature => filteredCellNames.has(feature.name) && getIsFeatureInFrame(feature, igvBrowser)
  )

  updateTrack(trackIndex, filteredFeatures, igv, igvBrowser)
}

// Uncomment to ease debugging
// window.SCP.filterByScore = filterByScore
// window.SCP.filterIgvFeatures = filterIgvFeatures

/**
 * Get tracks for selected TSV (e.g. BAM, BED) files, to show genomic features
 */
function getTracks(tsvAndIndexFiles, dataType) {
  const tsvTracks = []

  for (let i = 0; i < tsvAndIndexFiles.length; i++) {
    let tsvTrack = tsvAndIndexFiles[i]

    tsvTrack.oauthToken = getReadOnlyToken()
    tsvTrack.label = tsvTrack.name
    tsvTrack.indexURL = decodeURIComponent(tsvTrack.indexUrl)
    tsvTrack.url = decodeURIComponent(tsvTrack.url)
    tsvTrack.visibilityWindow = 1_000_000 // 1 Mbp
    if (dataType && dataType === 'atac-fragment') {
      const atacProps = {
        displayMode: 'SQUISHED',
        colorBy: 'score',
        height: 300,

        // "Score" in scATAC-seq BED files is more accurately "read count".
        //
        // Per Pipeline Development team, multiple reads per fragment per
        // barcode can occur due to technical factors like PCR duplicates,
        // sequencing errors, or low complexity regions.
        //
        // So this colors features in a sequential scale from a neutral grey
        // ("score": 1) to bright red ("score": 5/6).
        //
        // More context:
        // https://broadinstitute.slack.com/archives/CESEYJW9W/p1717148489885659?thread_ts=1717099893.194269&cid=CESEYJW9W
        //
        // Per 2024-06-05, it might be worth giving users finer-grained control
        // over the color table for their sequence file tracks.
        colorTable: {
          '1': '#AAA',
          '2': '#C88',
          '3': '#C66',
          '4': '#E44',
          '5': '#E44',
          '6': '#E44',
          '7': '#E44',
          '8': '#F00',
          '9': '#F00',
          '10': '#F00'
        },

        // "dataType" is an SCP-custom IGV track attribute, which lets us
        // distinguish between various kinds of BED file.
        //
        // TODO: Add an "ATAC fragment?" checkbox in "Sequence file" upload to
        // distinguish this type of BED from default (generic) BEDs.
        dataType: 'atac-fragment'
      }
      tsvTrack = Object.assign(tsvTrack, atacProps)
    }

    tsvTracks.push(tsvTrack)
  }

  return tsvTracks
}

/**
 * Gets the track of genes and transcripts from the genome's BED file
 */
function getGenesTrack(gtfFiles, genome, genesTrackName) {
  // gtfFiles assigned in _genome.html.erb
  const gtfFile = gtfFiles[genome].genome_annotations

  // SCP encodes these URLs, but IGV does too.  This avoids double-encoding.
  gtfFile.url = decodeURIComponent(gtfFile.url)
  gtfFile.indexUrl = decodeURIComponent(gtfFile.indexUrl)

  const genesTrack = {
    name: genesTrackName,
    url: gtfFile.url,
    indexURL: gtfFile.indexUrl,
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

/** Get genomic feature or coordinates to view in IGV */
function getDefaultLocus(queriedGenes, uniqueGenes, genomeId) {
  let fallbackLocus
  if (genomeId === 'Macaca_fascicularis_5.0') {
    fallbackLocus = 'chr1:1-2'
  } else {
    fallbackLocus = 'GAPDH'
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
  return locus
}

/** Get configuration options for IGV genome browser */
export function getIgvOptions(tracks, gtfFiles, uniqueGenes, queriedGenes) {
  let genomeId = tracks[0].genomeAssembly

  if (genomeId === 'GRCh38') {
    genomeId = 'hg38'
    gtfFiles[genomeId] = gtfFiles['GRCh38']
    delete gtfFiles['GRCh38']
  }

  if (genomeId === 'GRCm38') {
    genomeId = 'mm10'
    gtfFiles[genomeId] = gtfFiles['GRCm38']
    delete gtfFiles['GRCm38']
  }

  let reference
  let searchOptions
  if (genomeId === 'Macaca_fascicularis_5.0') {
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
    reference = genomeId
  }

  const locus = getDefaultLocus(queriedGenes, uniqueGenes, genomeId)

  const genesTrackName = `Genes | ${tracks[0].genomeAnnotation.name}`
  const genesTrack = getGenesTrack(gtfFiles, genomeId, genesTrackName)

  const otherTracks = getTracks(tracks.filter(track => track.format === 'bed'), 'atac-fragment')

  const bamTracks = getTracks(tracks.filter(track => track.format === 'bam'))
  const trackList = [genesTrack].concat(otherTracks, bamTracks)

  const igvOptions = { reference, locus, tracks: trackList, igvGenomeId: genomeId }

  if (typeof searchOptions !== 'undefined') {
    igvOptions['search'] = searchOptions
  }

  return igvOptions
}

/** Apply cell filtering to IGV, retryably */
function applyIgvFilters(retryAttempt=0, setIsLoadingFilters) {
  const filteredCellNames = window.SCP.filteredCellNames
  if (filteredCellNames) {
    filterIgvFeatures(filteredCellNames)
    setIsLoadingFilters(true)
  } else {
    if (retryAttempt < 20) {
      setTimeout(() => {
        applyIgvFilters(retryAttempt++)
      }, 250)
    }
  }
}

/** Find the ordinal position of an element among its sibling elements */
function getIndexAmongSiblings(node, siblingClass=null) {
  console.log('a')
  let siblings = node.parentNode.children
  console.log('b')
  if (siblingClass) {
    siblings = Array.from(siblings).filter(node => {
      return Array.from(node.classList).includes(siblingClass)
    })
  }
  console.log('c')
  for (let i = 0; i < siblings.length; i++) {
    if (siblings[i] === node) {return i}
  }
  console.log('d')
  return -1
}

/** Change transparency of a track's canvas graphics layer */
function updateTrackCanvasOpacity(spinner, opacity) {
  Array.from(spinner.parentNode.children)
    .find(node => node.tagName === 'CANVAS')
    .style.opacity = opacity

}

/** Force loading UI in track if it's loading filters; else don't force */
function ensureTrackLoadingVisuals(isLoadingFilters, containerId, igvBrowser) {
  const trackIndex = igvBrowser.tracks.findIndex(
    track => track.config?.dataType === 'atac-fragment'
  )

  const igvContainer = document.querySelector(`#${containerId}`)

  // Create a watcher for the IGV spinner, and update DOM as needed
  const mutationObserver = new MutationObserver(mutationRecords => {
    mutationRecords.forEach(mutationRecord => {
      const target = mutationRecord.target

      const isSpinner = Array.from(target?.classList).includes('igv-loading-spinner-container')
      if (isSpinner) {
        const thisTrackIndex = getIndexAmongSiblings(target.parentNode, 'igv-viewport')
        if (thisTrackIndex === trackIndex) {
          const isSpinnerHidden = target.style.display === 'none'

          if (isSpinnerHidden && isLoadingFilters) {
            console.log('show spinner')
            target.style.display = '' // Show spinner
            updateTrackCanvasOpacity(target, 0.1)
          } else {
            // TODO: Fix infinite loop caused by this commented-out code
            // console.log('hide spinner')
            // target.style.display = 'none' // Hide spinner
          }
        }
      }
    })
  })

  // mutObs.observe(igvContainer, { attributes: true, childList: true, subtree: true });
  mutationObserver.observe(igvContainer.shadowRoot, { attributes: true, subtree: true });

  // mutObs.observe(igvContainer.shadowRoot, { childList: true });

}

/**
 * Instantiates and renders igv.js widget on the page
 */
async function initializeIgv(
  containerId, tracks, gtfFiles, uniqueGenes, queriedGenes,
  igvCellFilteringSelection, isLoadingFilters, setIsLoadingFilters
) {
  // Bail if already displayed
  delete igv.browser

  const igvContainer = document.getElementById(containerId)
  igvContainer.innerHTML = ''

  const igvOptions = getIgvOptions(tracks, gtfFiles, uniqueGenes, queriedGenes)

  // Omit default IGV "RefSeq genes" track
  const originalInitializeGenomes = igv.GenomeUtils.initializeGenomes
  igv.GenomeUtils.initializeGenomes = async function(config) {
    await originalInitializeGenomes(config)
    igv.GenomeUtils.KNOWN_GENOMES[igvOptions.igvGenomeId].tracks = []
  }

  window.igv = igv
  const igvBrowser = await igv.createBrowser(igvContainer, igvOptions)
  window.igvBrowser = igvBrowser

  if (igvCellFilteringSelection) {
    applyIgvFilters(0, setIsLoadingFilters)
  }

  // Force loading UI in track if it's loading filters; else don't force
  ensureTrackLoadingVisuals(isLoadingFilters, containerId, igvBrowser)

  igvBrowser.on('trackclick', (track, popoverData) => {
    // Don't show popover when there's no data.
    if (!popoverData || !popoverData.length) {
      return false
    }

    let markup = '<div class="igv-popover"><div>'

    const spanStyle = 'style="font-weight: bolder"'

    popoverData.forEach(nameValue => {
      if (nameValue.name) {
        let name = nameValue.name
        const config = track.config
        if (config.format === 'bed' && config.dataType === 'atac-fragment') {
          const nameLc = name.toLowerCase()
          if (nameLc === 'score') {
            name = 'Read count'
          } else if (nameLc === 'name') {
            name = 'ATAC barcode'
          }
        }
        const value = nameValue.value
        markup += `<div><span ${spanStyle}>${ name }</span>&nbsp;&nbsp;&nbsp;${value}</div>`
      } else {
        // not a name/value pair
        markup += `<div>${ nameValue.toString() }</div>`
      }
    })

    markup += '</div></div>'

    // By returning a string from the trackclick handler we're asking IGV to use our custom HTML in its pop-over.
    return markup
  })

  igvBrowser.on('locuschange', () => {
    const filteredCellNames = window.SCP.filteredCellNames
    if (filteredCellNames) {
      filterIgvFeatures(filteredCellNames)
    }
  })

  log('igv:initialize')
}

