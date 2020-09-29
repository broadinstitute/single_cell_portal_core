/* eslint-disable no-unused-vars */

let ideogram
let checkboxes
let ideoConfig
let adjustedExpressionThreshold
let chrMargin

const legend = [{
  name: 'Expression level',
  rows: [
    { name: 'Low', color: '#00B' },
    { name: 'Normal', color: '#DDD' },
    { name: 'High', color: '#F00' }
  ]
}]

/** Get ideogram heatmap tracks selected via checkbox */
function getSelectedTracks() {
  const selectedTracks = []

  checkboxes.forEach(checkbox => {
    const trackIndex = parseInt(checkbox.getAttribute('id').split('_')[1])
    if (checkbox.checked) {
      selectedTracks.push(trackIndex)
    }
  })

  return selectedTracks
}

/** Set selected tracks as displayed tracks */
function updateTracks() {
  const selectedTracks = getSelectedTracks()
  ideogram.updateDisplayedTracks(selectedTracks)
}

/** Update space between chromosomes; called upon updating related slider */
function updateMargin(event) {
  chrMargin = parseInt(event.target.value)
  ideoConfig.chrMargin = chrMargin
  ideogram = new Ideogram(ideoConfig)
}

/** Create a slider to adjust space between chromosomes */
function addMarginControl() {
  chrMargin = (typeof chrMargin === 'undefined' ? 10 : chrMargin)
  const marginSlider =
      `<label
          id="chrMarginContainer"
          style="float:left; position: relative; top: 50px; left: -130px;">
        Chromosome margin
      <input
        type="range"
        id="chrMargin"
        list="chrMarginList" value="${chrMargin}">
      </label>
      <datalist id="chrMarginList">
        <option value="0" label="0%">
        <option value="10">
        <option value="20">
        <option value="30">
        <option value="40">
        <option value="50" label="50%">
        <option value="60">
        <option value="70">
        <option value="80">
        <option value="90">
        <option value="100" label="100%">
      </datalist>`
  d3.select('#_ideogramLegend').node().innerHTML += marginSlider
}

/** Change expression threshold; called upon updating related slider */
function updateThreshold(event) {
  let newThreshold

  const expressionThreshold = parseInt(event.target.value)

  adjustedExpressionThreshold = Math.round(expressionThreshold/10 - 4)
  const thresholds = window.originalHeatmapThresholds
  const numThresholds = thresholds.length
  ideoConfig.heatmapThresholds = []

  // If expressionThreshold > 1,
  //    increase thresholds above middle, decrease below
  // If expressionThreshold < 1,
  //    decrease thresholds above middle, increase below
  for (let i = 0; i < numThresholds; i++) {
    if (i + 1 > numThresholds/2) {
      newThreshold = thresholds[i + adjustedExpressionThreshold]
    } else {
      newThreshold = thresholds[i - adjustedExpressionThreshold]
    }
    ideoConfig.heatmapThresholds.push(newThreshold)
  }
  ideogram = new Ideogram(ideoConfig)
}

/** Create slider to adjust expression threshold for "gain" or "loss" calls */
function addThresholdControl() {
  if (typeof(expressionThreshold) === 'undefined') {
    window.expressionThreshold = 50
    window.originalHeatmapThresholds =
      ideogram.rawAnnots.metadata.heatmapThresholds
  }

  const expressionThresholdSlider =
    `<label id="expressionThresholdContainer" style="float: left">
      <span
        class="glossary"
        title="Denoiser.  Adjusts mapping between inferCNV's output heatmap
          threshold values and normal vs. loss/gain signal.  Analogous to
          inferCNV denoise parameters, e.g. --noise_filter."
        style="cursor: help;">
      Expression threshold
      </span>
      <input
        type="range"
        id="expressionThreshold"
        list="expressionThresholdList"
        value="${window.expressionThreshold}"
      >
      <datalist id="expressionThresholdList">
        <option value="0" label="0.">
        <option value="10">
        <option value="20">
        <option value="30">
        <option value="40">
        <option value="50" label="1">
        <option value="60">
        <option value="70">
        <option value="80">
        <option value="90">
        <option value="100" label="1.5">
      </datalist>
      <br/><br/>`
  d3.select('#_ideogramLegend').node().innerHTML += expressionThresholdSlider
}

/** Handle updates to slider controls for ideogram display */
function ideoRangeChangeEventHandler(event) {
  const id = event.target.id
  if (id === 'expressionThreshold') updateThreshold(event)
  if (id === 'chrMargin') updateMargin(event)
}

/** Add sliders to adjust ideogram display */
function addIdeoRangeControls() {
  addThresholdControl()
  addMarginControl()

  document.removeEventListener('change', ideoRangeChangeEventHandler)
  document.addEventListener('change', ideoRangeChangeEventHandler)
}

/** Create interactive filters for ideogram tracks */
function createTrackFilters() {
  let i; let listItems; let checked

  addIdeoRangeControls()

  // Only apply this function once
  if (document.querySelector('#filter_1')) return
  listItems = ''
  const trackLabels = ideogram.rawAnnots.keys.slice(6)
  const displayedTracks = ideogram.config.annotationsDisplayedTracks
  for (i = 0; i < trackLabels.length; i++) {
    checked = (displayedTracks.includes(i + 1)) ? 'checked' : ''
    listItems +=
      `${'<li>' +
        '<label for="filter_'}${i + 1}">` +
          `<input type="checkbox" id="filter_${i + 1}" ${checked}/>${
            trackLabels[i]
          }</label>` +
      `</li>`
  }
  const content = `Tracks ${listItems}`
  document.querySelector('#tracks-to-display').innerHTML = content


  $('#filters-container').after(
    '<div id="ideogramTitle">Copy number variation inference</div>'
  )

  checkboxes = document.querySelectorAll('input[type=checkbox]')
  checkboxes.forEach(checkbox => {
    checkbox.addEventListener('click', () => {
      updateTracks()
    })
  })
}

/**
 * Note ideogram is unavailable for this numeric cluster
 *
 * Used in render_cluster.js.erb
 */
function warnIdeogramOfNumericCluster() {
  const cluster = $('#cluster option:selected').val()
  const cellAnnot = $('#annotation option:selected').val()

  const warning =
    `${'<div id="ideogramWarning" style="height: 400px; margin-left: 20px;">' +
      'Ideogram not available for selected cluster ("'}${cluster}") and ` +
      `cell annotation ("${cellAnnot}").` +
    `</div>`

  $('#tracks-to-display, #_ideogramOuterWrap').html('')
  $('#ideogramWarning, #ideogramTitle').remove()
  $('#ideogram-container').append(warning)
}

/** Initialize ideogram to visualize genomic heatmap from inferCNV  */
function initializeIdeogram(url) {
  if (typeof window.ideogram !== 'undefined') {
    delete window.ideogram
    $('#tracks-to-display').html('')
    $('#_ideogramOuterWrap').html('')
  }

  $('#ideogramWarning, #ideogramTitle').remove()

  ideoConfig = {
    container: '#ideogram-container',
    organism: window.ideogramInferCnvSettings.organism.toLowerCase(),
    assembly: window.ideogramInferCnvSettings.assembly,
    dataDir: 'https://unpkg.com/ideogram@1.20.0/dist/data/bands/native/',
    annotationsPath: url,
    annotationsLayout: 'heatmap',
    legend,
    onDrawAnnots: createTrackFilters,
    debug: true,
    rotatable: false,
    chrMargin: 10,
    chrHeight: 80,
    annotationHeight: 20,
    geometry: 'collinear',
    orientation: 'horizontal'
  }

  ideogram = new Ideogram(ideoConfig)

  // Log Ideogram.js initialization in Google Analytics
  ga('send', 'event', 'ideogram', 'initialize')

  window.SCP.log('ideogram:initialize')
}
