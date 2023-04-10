import React, { useEffect, useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faPalette, faExternalLinkAlt, faTimes, faSearch } from '@fortawesome/free-solid-svg-icons'
import Modal from 'react-bootstrap/lib/Modal'
import { HexColorPicker, HexColorInput } from 'react-colorful'
import Button from 'react-bootstrap/lib/Button'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import debounce from 'lodash.debounce'


import { log } from '~/lib/metrics-api'
import PlotUtils from '~/lib/plot'
const { scatterLabelLegendWidth, getColorForLabel, getLegendSortedLabels } = PlotUtils

/** Convert state Boolean to attribute string */
function getActivity(isActive) {
  return isActive ? 'active' : 'disabled'
}

/** Component for row in legend */
function LegendEntry({
  label, numPoints, iconColor, correlations, numLabels, hiddenTraces, updateHiddenTraces,
  showColorControls, updateEditedCustomColors, setActiveTraceLabel, showLegendSearch
}) {
  let entry = label
  // whether to show the color picker modal
  const [showColorPicker, setShowColorPicker] = useState(false)
  // the current user-picked (though not necessarily saved) color
  // note that the color picker components do not allow invalid inputs, so we don't need to do any additional validation
  const [pickedColor, setPickedColor] = useState(iconColor)
  const hasCorrelations = correlations !== null
  if (correlations) {
    const correlation = Math.round(correlations[label] * 100) / 100

    // ρ = rho = Spearman's rank correlation coefficient
    entry = `${label} (${numPoints} points, ρ = ${correlation})`
  }

  const isShown = hiddenTraces.includes(label)

  const iconStyle = { backgroundColor: iconColor }
  const shownClass = (isShown ? '' : 'shown')

  /** Toggle state of this legend filter, and accordingly upstream */
  function toggleSelection(event) {
    const wasShown = !isShown
    updateHiddenTraces(label, wasShown)

    const legendEntry = {
      label, numPoints, numLabels, wasShown, iconColor,
      hasCorrelations
    }
    log('click:scatterlegend:single', legendEntry)
  }

  /** handle 'ok' press by updating the colors to the parent, and closing the dialog */
  function handleColorPicked() {
    updateEditedCustomColors(label, pickedColor)
    setShowColorPicker(false)
  }

  /**
   * If there are 200 or more labels for the annotation add a delay for hover functionality for
   * mouse events on the legend for better performance.
   */
  const delayTimeForHover = (numLabels >= 200) ? 700 : 0

  /**
   * Handle mouse-enter-events, used for hovering, by wrapping setActiveTraceLabel in a debounce,
   * this will delay the call to setActiveTraceLabel and can be canceled. These enhancements
   * will reduce the calls to setActiveTraceLabel that occur from quick mouse movements in the legend.
   */
  const debouncedHandleMouseEnter = debounce(() => {
    setActiveTraceLabel(label)
  }, delayTimeForHover) // ms to delay the call to setActiveTraceLabel()

  /**
   * Cancel the call to update the active label from the debounced-mouse-leave function
   * and call the debounced-mouse-enter function
   */
  function handleOnMouseEnter() {
    debouncedHandleMouseLeave.cancel()
    debouncedHandleMouseEnter()
  }

  /**
   * Cancel the call to update the active label from the debounced-mouse-enter function
   * and call the debounced-mouse-leave function
   */
  function handleOnMouseLeave() {
    debouncedHandleMouseEnter.cancel()
    debouncedHandleMouseLeave()
  }

  /**
   * Handle mouse leave events by resetting the active label, and wrap this call in a debounce
   * so that it can be delayed and canceled to reduce the calls to setActiveTraceLabel that occur
   * from quick mouse movements in the legend.
   */
  const debouncedHandleMouseLeave = debounce(() => {
    setActiveTraceLabel('')
  }, delayTimeForHover) // ms to delay the call to setActiveTraceLabel()


  // clicking the label will either hide the trace, or pop up a color picker
  const entryClickFunction = showColorControls ? () => setShowColorPicker(true) : toggleSelection

  return (
    <>
      <div
        className={`scatter-legend-row ${shownClass}`}
        role="button"
        onClick={entryClickFunction}

        onMouseEnter={handleOnMouseEnter}
        onMouseLeave={handleOnMouseLeave}
      >
        <div className="scatter-legend-icon" style={iconStyle}>
          { showColorControls && <FontAwesomeIcon icon={faPalette} title="Change the color for this label"/> }
        </div>
        <div className="scatter-legend-entry">
          <span className="legend-label" title={entry}>{entry}</span>
          <span className="num-points" title={`${numPoints} points in this group`}>{numPoints}</span>
        </div>
      </div>
      { showColorPicker && !showLegendSearch &&
        <Modal
          id='color-picker-modal'
          show={showColorPicker}
          onHide={() => setShowColorPicker(false)}
          animation={false}
          bsSize='small'>
          <Modal.Body>
            <div className="flexbox-align-center flexbox-column">
              <span>Select color</span>
              <span className="flexbox-align-center">
                #<HexColorInput color={pickedColor} onChange={setPickedColor}/>
                &nbsp;
                <span className="preview-block" style={{ background: pickedColor }}></span>
              </span>
              <HexColorPicker color={pickedColor} onChange={setPickedColor}/>
            </div>
          </Modal.Body>
          <Modal.Footer>
            <button className="btn btn-primary" onClick={handleColorPicked}>OK</button>
            <button className="btn terra-btn-secondary" onClick={() => setShowColorPicker(false)}>Cancel</button>
          </Modal.Footer>
        </Modal>
      }
    </>
  )
}

/** Handle click on "Show all" or "Hide all" button */
function showHideAll(showOrHide, labels, updateHiddenTraces) {
  if (showOrHide === 'show') {
    updateHiddenTraces(labels, false, true)
  } else {
    updateHiddenTraces(labels, true, true)
  }
}

/** Get status of "Show all" and "Hide all" links */
function getShowHideEnabled(hiddenTraces, countsByLabel) {
  const numHiddenTraces = hiddenTraces.length
  const numLabels = Object.keys(countsByLabel).length

  let enabled = [true, true] // [isShowAllEnabled, isHideAllEnabled]

  if (countsByLabel === null) {
    // When nothing has loaded yet
    enabled = [false, false]
  } else if (numHiddenTraces === numLabels) {
    // When all groups are hidden
    enabled = [true, false]
  } else if (numHiddenTraces < numLabels && numHiddenTraces > 0) {
    // When some groups are hidden and some are shown
    enabled = [true, true]
  } else if (numHiddenTraces === 0) {
    // When no groups are hidden
    enabled = [false, true]
  }

  return enabled
}

/** Component for custom legend for scatter plots */
export default function ScatterPlotLegend({
  name, height, countsByLabel, correlations, hiddenTraces,
  updateHiddenTraces, customColors, editedCustomColors, setEditedCustomColors, setCustomColors,
  enableColorPicking=false, activeTraceLabel, setActiveTraceLabel,
  isSplitLabelArrays, updateIsSplitLabelArrays, hasArrayLabels,
  externalLink, saveCustomColors
}) {
  // is the user currently in color-editing mode
  const [showColorControls, setShowColorControls] = useState(false)
  // whether a request to the server to save colors is pending
  const labels = getLegendSortedLabels(countsByLabel)
  const numLabels = labels.length

  const [labelsToShow, setLabelsToShow] = useState(labels)

  const style = { width: scatterLabelLegendWidth, height }
  const filteredClass = (hiddenTraces.length === 0) ? 'unfiltered' : ''
  const [showIsEnabled, hideIsEnabled] =
    getShowHideEnabled(hiddenTraces, countsByLabel)

  const flags = getFeatureFlagsWithDefaults()

  // filter text for searching the legend
  const [filter, setFilter] = useState('')

  /** updates the user picked color for the given label.  does *not* save change to the server */
  function updateEditedCustomColors(label, color) {
    editedCustomColors[label] = color
    setEditedCustomColors({ ...editedCustomColors })
  }

  /** resets any unsaved changes to user colors */
  function cancelColors() {
    setEditedCustomColors({})
    setShowColorControls(false)
  }

  /** resets any unsaved changes to user colors and clears custom colors */
  async function resetColors() {
    setEditedCustomColors({})
    await saveCustomColors({})
    setShowColorControls(false)
  }

  /** save the colors to the server */
  async function saveColors() {
    // merge the user picked colors with existing custom colors so previously saved values are preserved
    const colorsToSave = Object.assign(customColors, editedCustomColors)
    await saveCustomColors(colorsToSave)
    setShowColorControls(false)
  }

  /** collect general information when a user's mouse enters the legend  */
  function logMouseEnter() {
    log('hover:scatterlegend', { numLabels })
  }

  /** create mapping of labels and colors of full label list (used for filtered legends) */
  const fullLabelsMappedToColor = labels.map((label, i) => {
    const iconColor = getColorForLabel(label, customColors, editedCustomColors, i)
    return { label, iconColor }
  })

  /** retrieve the color for the label specified (used for filtered legends) */
  function getColorForLabelIcon(specifiedLabel) {
    const labelAndColor = fullLabelsMappedToColor.find(legendItem => legendItem.label === specifiedLabel)
    return labelAndColor.iconColor
  }

  /** Update the labels to be shown in the legend based on the user filtering (used for filtered legends) */
  useEffect(() => {
    let filteredLabels
    if (filter === '') {
      filteredLabels = labels
    } else {
      const lowerCaseFilter = filter.toLowerCase()
      filteredLabels = labels.filter(f => f.toLowerCase().includes(lowerCaseFilter))
    }

    setLabelsToShow(filteredLabels)
  }, [filter])

  /** Update the labels to be shown in the legend when the counts by label changes (needed for split array labels)  */
  useEffect(() => {
    setLabelsToShow(labels)
  }, [countsByLabel])

  /** only show the clear button if there is input in the filter searchbar (used for filtered legends) */
  const showClear = !!filter

  /** only show the legend search if there are greater than 30 labels in the legend and flag is enabled */
  const showLegendSearch = numLabels >= 30 && flags?.legend_search

  /** handle a user pressing the 'x' to clear the field */
  function handleClear() {
    setFilter('')
    setLabelsToShow(labels)
  }

  return (
    <div
      className={`scatter-legend ${filteredClass}`}
      onMouseEnter={logMouseEnter}
      style={style}>
      <div className="scatter-legend-head">
        {externalLink.url &&
        <div className="cluster-external-link-container">
          <a
            className="cluster-external-link"
            href={externalLink.url}
            target="blank"
            data-toggle="tooltip"
            data-original-title={externalLink.description}
          >
            {externalLink.title}&nbsp;&nbsp;<FontAwesomeIcon icon={faExternalLinkAlt}/>
          </a>
        </div>
        }
        <p className="scatter-legend-name">{name}</p>
        { (hasArrayLabels && !showLegendSearch) &&
            <div>
              { isSplitLabelArrays &&
                <a
                  role="button"
                  data-analytics-name='split-traces-unsplit'
                  onClick={() => {
                    updateIsSplitLabelArrays(false)
                    updateHiddenTraces([], false, true) // TODO (SCP-4623), remove this line once ticket is complete
                  }}
                >Merge array labels</a>
              }
              { !isSplitLabelArrays &&
                <a
                  role="button"
                  data-analytics-name='split-traces-split'
                  onClick={() => {
                    updateIsSplitLabelArrays(true)
                    updateHiddenTraces([], false, true) // TODO (SCP-4623), remove this line once ticket is complete
                  }}
                >Split array labels</a>
              }
            </div>
        }
        { enableColorPicking && !showLegendSearch &&
          <div>
            { showColorControls &&
              <>
                <span>Click a label to select a new color</span><br/>
                <div>
                  <a role="button" data-analytics-name="legend-color-picker-save" onClick={saveColors}>
                    Save colors
                  </a>
                  <a role="button" className="pull-right" data-analytics-name="legend-color-picker-cancel" onClick={cancelColors}>
                    Cancel
                  </a><br/>
                  &nbsp;
                  <a role="button" className="pull-right" data-analytics-name="legend-color-picker-reset" onClick={resetColors}>
                    Reset to defaults
                  </a>
                </div>
              </>
            }
            { !showColorControls &&
              <a role="button" data-analytics-name="legend-color-picker-show" onClick={() => setShowColorControls(true)}>
                Customize colors <FontAwesomeIcon icon={faPalette}/>
              </a>
            }
          </div>
        }
        <div>
          {numLabels > 1 && !showColorControls &&
          <>
            <a
              role="button"
              data-analytics-name='legend-show-all'
              className={`stateful-link ${getActivity(showIsEnabled)}`}
              disabled={!showIsEnabled}
              onClick={() => {showHideAll('show', labels, updateHiddenTraces)}}
            >Show all</a>
            <a
              role="button"
              data-analytics-name='legend-hide-all'
              className={`stateful-link pull-right ${getActivity(hideIsEnabled)}`}
              disabled={!hideIsEnabled}
              onClick={() => {showHideAll('hide', labels, updateHiddenTraces)}}
            >Hide all</a>
          </>
          }
        </div>
        {(!showColorControls && showLegendSearch) && <div className='legend-search'>
          <span className='legend-search-icon'><FontAwesomeIcon icon={faSearch} /></span>
          <input
            id="filter"
            data-analytics-name='legend-search'
            name="filter"
            type="text"
            className='no-border'
            placeholder='Search'
            value={filter}
            onChange={event => setFilter(event.target.value)}
          />
          { showClear && <Button
            type='button'
            data-analytics-name='clear-legend-search'
            className='legend-search-icon'
            onClick={handleClear} >
            <FontAwesomeIcon icon={faTimes} />
          </Button> }
        </div>}
        {labelsToShow.map((label, i) => {
          const numPoints = countsByLabel[label]
          const iconColor = showLegendSearch ?
            getColorForLabelIcon(label) :
            getColorForLabel(label, customColors, editedCustomColors, i)
          return (
            <LegendEntry
              key={label}
              label={label}
              numPoints={numPoints}
              iconColor={iconColor}
              correlations={correlations}
              hiddenTraces={hiddenTraces}
              updateHiddenTraces={updateHiddenTraces}
              numLabels={labelsToShow.length}
              updateEditedCustomColors={updateEditedCustomColors}
              showColorControls={showColorControls}
              setActiveTraceLabel={setActiveTraceLabel}
              showLegendSearch={showLegendSearch}
            />
          )
        })}
      </div>
    </div>
  )
}
