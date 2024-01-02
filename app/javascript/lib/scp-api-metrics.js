/**
 * @fileoverview Functions for client-side usage analytics of SCP REST API
 */
import { formatTerms } from './search-metrics'
import { log } from './metrics-api'

/** Logs violin plot metrics */
export function logViolinPlot(
  { genes, plotType, showPoints },
  perfTimes
) {
  const props = { genes, plotType, showPoints, perfTimes }

  log('plot:violin', props)
}

let numScatterPlotsSincePageLoad = 0
/** Logs scatter plot metrics */
export function logScatterPlot(
  { scatter, genes },
  perfTimes
) {
  numScatterPlotsSincePageLoad += 1
  const props = {
    'numPoints': scatter.numPoints, // How many cells are we plotting?
    genes,
    'genesPlotted': scatter.genes,
    'is3D': scatter.is3D,
    'numPointsPlotted': scatter.data.cells.length,
    'isSubsampled': scatter.isSubsampled,
    'subsample': scatter.subsample,
    'layout:width': scatter.width, // Pixel width of graph
    'layout:height': scatter.height, // Pixel height of graph
    'numAnnotSelections': scatter.annotParams.values.length,
    'annotName': scatter.annotParams.name,
    'annotType': scatter.annotParams.type,
    'annotScope': scatter.annotParams.scope,
    'isCorrelatedScatter': scatter.isCorrelatedScatter,
    'isAnnotatedScatter': scatter.isAnnotatedScatter,
    'isSpatial': scatter.isSpatial,
    perfTimes,
    numScatterPlotsSincePageLoad
  }

  log('plot:scatter', props)
}

/**
 * Log create user annotation metrics
 */
export function logCreateUserAnnotation() {
  ga('send', 'event', 'engaged_user_action', 'create_custom_cell_annotation')
  log('create-custom-cell-annotation')
}

/**
 * Get common plot log event properties
 *
 * TODO as part of SCP-2736:
 * - Remove jQuery, generalize to also handle plot from React
 */
export function getLogPlotProps() {
  const genes = formatTerms($('#search_genes').val())

  const logProps = {
    currentTab: $('#view-tabs .study-nav.active').text().trim().toLowerCase(),
    genes,
    numGenes: genes.length,
    cluster: $('#search_cluster').val(),
    annotation: $('#search_annotation').val(),
    subsample: $('#search_subsample').val()
  }

  return logProps
}

/**
 * Extract the number of Azul files that have been chosen for download
 */
function getNumAzulFiles(azulFiles={}) {
  let totalNumFiles = 0
  for (const studyEntry of Object.entries(azulFiles)) {
    const [azulStudyId, fileList] = studyEntry
    totalNumFiles += fileList.length
  }

  return totalNumFiles
}

/**
 * Log when a download is authorized and the number of files from each source that are being downloaded.
 * fileIds is an array containing the file ids for SCP sourced files
 * azulFiles is an object with file info sourced from HCA files
 *
 * This is our best web-client-side methodology for measuring downloads.
 */
export function logDownloadAuthorization(perfTimes, fileIds, azulFiles) {
  const numAzulFiles = getNumAzulFiles(azulFiles)
  const props = { perfTimes, 'numSCPFiles': fileIds.length, numAzulFiles }
  log('download-authorization', props)
  ga('send', 'event', 'advanced-search', 'download-authorization') // eslint-disable-line no-undef, max-len
}
