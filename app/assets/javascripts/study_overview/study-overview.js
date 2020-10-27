/**
* @fileoverview Default view of Explore tab in Study Overview
*
* Shows "Clusters" and sometimes "Genomes", etc.
*/

const study = window.SCP.study

window.SCP.startPendingEvent('user-action:page:view:site-study',
  { speciesList: window.SCP.taxons },
  'plot:',
  true)

/** Draws the scatter plot for the default Explore tab view */
function renderScatter() {
  // detach listener as it will be re-attached in response;
  // this helps reduce spurious errors
  $(window).off('resizeEnd')

  const target = $('#cluster-plot')[0]
  const spinner = new Spinner(window.opts).spin(target)
  $('#cluster-plot').data('spinner', spinner)

  const urlParams = window.getRenderUrlParams()
  const url = `${study.renderClusterPath}?${urlParams}`

  $.ajax({
    url,
    method: 'GET',
    dataType: 'script'
  })
}

// For inferCNV ideogram
$('#ideogram_annotation').on('change', function() {
  const ideogramFiles = study.ideogramFiles
  const fileId = $(this).val() // eslint-disable-line
  if (fileId !== '') {
    const ideogramAnnot = ideogramFiles[fileId]
    window.ideogramInferCnvSettings = ideogramAnnot.ideogram_settings
    window.initializeIdeogram(ideogramAnnot.ideogram_settings.annotationsPath)
  } else {
    $('#tracks-to-display, #_ideogramOuterWrap').html('')
    $('#ideogramTitle').remove()
  }
})

if (study.canVisualizeClusters) {
  $('#cluster-plot').data('rendered', false)

  const baseCamera = {
    'up': { 'x': 0, 'y': 0, 'z': 1 },
    'center': { 'x': 0, 'y': 0, 'z': 0 },
    'eye': { 'x': 1.25, 'y': 1.25, 'z': 1.25 }
  }

  $(document).ready(() => {
    // if tab position was specified in url, show the current tab
    if (window.location.href.split('#')[1] !== '') {
      const tab = window.location.href.split('#')[1]
      $(`#study-tabs a[href="#${tab}"]`).tab('show')
    }
    $('#cluster-plot').data('camera', baseCamera)
    // set default subsample option of 10K (if subsampled) or all cells
    if (window.SCP.numPointsCluster > 10000 && window.SCP.clusterIsSampled) {
      $('#subsample').val(10000)
      $('#search_subsample').val(10000)
    }

    renderScatter()
  })

  // listener for cluster nav, specific to study page
  $('#annotation').change(function() {
    $('#cluster-plot').data('rendered', false)
    const an = $(this).val() // eslint-disable-line
    // keep track for search purposes
    $('#search_annotation').val(an)
    $('#gene_set_annotation').val(an)
    renderScatter()
  })

  $('#subsample').change(function() {
    $('#cluster-plot').data('rendered', false)
    const sample = $(this).val() // eslint-disable-line
    $('#search_subsample').val(sample)
    $('#gene_set_subsample').val(sample)
    renderScatter()
  })

  $('#cluster').change(function() {
    $('#cluster-plot').data('rendered', false)
    const newCluster = $(this).val() // eslint-disable-line
    // keep track for search purposes
    $('#search_cluster').val(newCluster)
    $('#gene_set_cluster').val(newCluster)
    // grab currently selected annotation
    const currSubsample = $('#subsample').val()

    const params = [
      'cluster=', encodeURIComponent(newCluster),
      '&subsample=', encodeURIComponent(currSubsample)
    ].join('')
    const url = `${window.SCP.getNewAnnotationsPath}?${params}`

    // get new annotation options and re-render
    $.ajax({
      url,
      method: 'GET',
      dataType: 'script',
      complete(jqXHR, textStatus) {
        window.renderWithNewCluster(textStatus, renderScatter)
      }
    })
  })

  if (window.SCP.hasIdeogramInferCnvFiles) {
    // user has no clusters, but does have ideogram annotations
    $(document).ready(() => {
      const ideogramSelect = $('#ideogram_annotation')
      const firstIdeogram = $('#ideogram_annotation option')[1].value

      // manually trigger change to cause ideogram to render
      ideogramSelect.val(firstIdeogram).trigger('change')
    })
  }
}
