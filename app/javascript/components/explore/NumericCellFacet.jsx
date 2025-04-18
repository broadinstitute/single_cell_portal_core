/**
 * @fileoverview Easy, rich query builder for numeric annotations
 *
 * Numeric cell facets provide:
 * - Histogram for seeing distributions you can select from
 * - Range slider (a.k.a. brush)
 * - Inputs fields for manual numeric input
 * - Operator menu
 * - Support for special (but common) "not available" values, i.e. "N/A"
 * - Reset button, expand / collapse button
 *
 * Each eligible numeric annotation gets one numeric cell facet.  Numeric
 * facets combine with other ("group" / categorical or numeric facets),
 * logically joining via the "AND" Boolean operator across facets.
 *
 * More context and demo video:
 * https://github.com/broadinstitute/single_cell_portal_core/pull/1988
 */

import React, { useState, useEffect } from 'react'
import _isEqual from 'lodash/isEqual'
import SVGBrush from 'react-svg-brush'

import { FacetHeader } from '~/components/explore/FacetComponents'
import { round } from '~/lib/metrics-perf'
import { getMinMaxValues } from '~/lib/cell-faceting.js'
import { scaleLinear } from '~/lib/scale-linear.js'

const HISTOGRAM_BAR_MAX_HEIGHT = 20
const SLIDER_HANDLEBAR_WIDTH = 6

/**
 * Get SVG for handlebar UI, as an affordance for resizing
 *
 * Inspired by https://crossfilter.github.io/crossfilter
 */
function getHandlebarPath(d) {
  const sweepFlag = d.type === 'e' ? 1 : 0
  const x = sweepFlag ? 1 : -1
  const y = HISTOGRAM_BAR_MAX_HEIGHT
  const width = SLIDER_HANDLEBAR_WIDTH

  // Construct an SVG arc
  // Docs: https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths#arcs
  const start = `M${ .5 * x },${ y}`
  const rx = width
  const ry = width
  const xAxisRotation = 0
  const largeArcFlag = 0
  const arc1X = ((width + 0.5) * x)
  const arc1Y = y + 6
  const arc1EndLine = `V${ 2 * y - width}`
  const arc2X = 0.5 * x
  const arc2Y = 2 * y
  const arc1 = `A${rx},${ry} ${xAxisRotation} ${largeArcFlag} ${sweepFlag} ${arc1X},${arc1Y}`
  const arc2 = `A${rx},${ry} ${xAxisRotation} ${largeArcFlag} ${sweepFlag} ${arc2X},${arc2Y}`

  /* eslint-disable */
  // Each handlebar has two vertical lines in it, resembling notched grooves
  const notches = (
    "M" + (2.5 * x) + "," + (y + (width + 2)) +
    "V" + (2 * y - (width + 2)) +
    "M" + (4.5 * x) + "," + (y + (width + 2)) +
    "V" + (2 * y - (width + 2))
  )
  /* eslint-enable */

  /* eslint-disable */
  return (
    start +
    arc1 +
    arc1EndLine +
    arc2 +
    "Z" +
    notches
  )
  /* eslint-enable */
}

/** Get display attributes for histogram bars */
function getHistogramBarDisplayAttrs(bars, maxCount) {
  const barRectAttrs = []
  const maxHeight = HISTOGRAM_BAR_MAX_HEIGHT
  bars.forEach((bar, i) => {
    const height = maxHeight * (bar.count / maxCount)
    const width = 11
    const attrs = Object.assign({
      x: (width + 1) * i,
      y: maxHeight - height + 1,
      width,
      height,
      color: (bar.isNull) ? '#888' : '#3D5A87'
    }, bar)
    barRectAttrs.push(attrs)
  })
  return barRectAttrs
}

/** Get histogram to show with numeric filter */
function getHistogramBars(filters) {
  const [minValue, maxValue, hasNull] = getMinMaxValues(filters)

  const numBins = 15
  const numBinsNullTrimmed = hasNull ? numBins - 2 : numBins
  const binSize = (maxValue - minValue) / numBinsNullTrimmed
  let bars = []

  for (let i = 0; i < numBins; i++) {
    const isNull = hasNull && i < 2
    let start
    let end
    const indexNullTrimmed = hasNull ? i - 2 : i
    if (isNull) {
      start = null
      end = null
    } else {
      start = minValue + (binSize * indexNullTrimmed)
      end = minValue + (binSize * (indexNullTrimmed + 1))
    }

    const bar = { count: 0, start, end, isNull }
    bars.push(bar)
  }

  for (let i = 0; i < filters.length; i++) {
    const [value, count] = filters[i]
    for (let j = 0; j < bars.length; j++) {
      const bar = bars[j]
      if (j < 2 && bar.isNull) {
        if (value === null) {
          // Account for 0-height "spacer" bar between null and non-null bars
          const adjustedCount = (j === 1) ? 0 : count
          // Count number of cells that have no numeric value for this annotation
          bars[j].count += adjustedCount
        }
      } else if (j < bars.length - 1) {
        // If not last bar, use exclusive (<) upper-bound to avoid double-count
        if (bar.start <= value && value < bar.end) {
          bars[j].count += count
        }
      } else {
        // If last bar, use inclusive (<=) upper-bound to avoid omitting maximum
        if (bar.start <= value && value <= bar.end) {
          bars[j].count += count
        }
      }
    }
  }

  let maxCount = 0
  for (let i = 0; i < bars.length; i++) {
    const count = bars[i].count
    if (count > maxCount) {maxCount = count}
  }

  bars = getHistogramBarDisplayAttrs(bars, maxCount)

  return bars
}

/** Get container offsets for brush */
function getSliderStyle(bars, histogramWidth) {
  const barWidth = bars[0].width
  const hasNull = bars[0].isNull

  const sliderLeft = hasNull ? 0 : -1 * (SLIDER_HANDLEBAR_WIDTH + 1)
  const sliderWidth = histogramWidth + (hasNull ? barWidth : 2 * SLIDER_HANDLEBAR_WIDTH + 2)

  const extentStartX = hasNull ? 2 * barWidth + 2 : SLIDER_HANDLEBAR_WIDTH + 2
  const extentWidth = hasNull ? histogramWidth : histogramWidth + SLIDER_HANDLEBAR_WIDTH

  return [sliderLeft, sliderWidth, extentStartX, extentWidth]
}

/** Histogram for distribution of numeric annotation values, with tooltips or slider */
function Histogram({
  facet, bars, histogramWidth, histogramHeight, operator,
  brushSelection, handleBrushMove, handleBrushEnd
}) {
  const sliderId = `numeric-filter-histogram-slider___${facet.annotation}`
  const [sliderLeft, sliderWidth, extentStartX, extentWidth] = getSliderStyle(bars, histogramWidth)
  const handlebarY = -1 * (HISTOGRAM_BAR_MAX_HEIGHT - 1)

  return (
    <>
      <svg
        height={histogramHeight}
        width={histogramWidth}
        style={{ borderBottom: '1px solid #AAA  ' }}
        className="numeric-filter-histogram"
      >
        {bars.map((bar, i) => {
          return (
            <rect
              fill={bar.color}
              x={bar.x}
              y={bar.y}
              width={bar.width}
              height={bar.height}
              key={i}
            />
          )
        })}
      </svg>
      {!['between', 'not between'].includes(operator) &&
        <div style={{ position: 'absolute', top: 0 }} key={2}>
          {bars.map((bar, i) => {
            let criteria
            if (bar.start === null) {
              criteria = 'N/A'
            } else {
              const briefStart = round(bar.start, 2)
              const briefEnd = round(bar.end, 2)
              criteria = `${briefStart}&nbsp;-&nbsp;${briefEnd}`
            }
            const tooltipContent = `<span>${criteria}:<br/>${bar.count}&nbsp;cells</span>`

            return (
              <span
                style={{
                  display: 'inline-block',
                  width: bar.width + 1,
                  height: HISTOGRAM_BAR_MAX_HEIGHT
                }}
                data-toggle="tooltip"
                data-html={true}
                data-original-title={tooltipContent}
                key={i}
              >
              </span>
            )
          })}
        </div>
      }
      {['between', 'not between'].includes(operator) &&
      <div>
        <svg
          height={histogramHeight}
          width={sliderWidth}
          style={{ position: 'absolute', top: 0, left: sliderLeft }}
          className="numeric-filter-histogram-slider"
          id={sliderId}
        >
          <path
            className="handlebar"
            fill="#EEE"
            fillOpacity="0.8"
            stroke="#000"
            strokeWidth="0.5"
            cursor="ew-resize"
            d={getHandlebarPath({ type: 'w' })}
            transform={`translate(${ brushSelection[0] }, ${handlebarY})`}
          />
          <path
            className="handlebar"
            fill="#EEE"
            fillOpacity="0.8"
            stroke="#000"
            strokeWidth="0.5"
            cursor="ew-resize"
            d={getHandlebarPath({ type: 'e' })}
            transform={`translate(${ brushSelection[1] }, ${handlebarY})`}
          />
          <SVGBrush // docs: https://github.com/kenns29/react-svg-brush#react-svg-brush
            // `extent` is the maximum rectangular boundary of the brush.
            // The format is [[x0, y0], [x1, y1]]
            extent={[
              [extentStartX, 0],
              [extentWidth, histogramHeight]
            ]}
            // `selection` is the current rectangular boundary of the brush
            // `brushSelection` is the current 1D range of the brush
            selection={[
              [brushSelection[0], 0],
              [brushSelection[1], histogramHeight]
            ]}
            // Get mouse position relative to SVG (instead of relative to page).
            // By default, getEventMouse returns [event.clientX, event.clientY]
            getEventMouse={event => {
              const { clientX, clientY } = event
              const { left, top } = document.querySelector(`#${sliderId}`).getBoundingClientRect()
              return [clientX - left, clientY - top]
            }}
            brushType="x" // i.e., 1D brush
            // onBrushStart={handleBrushStart}
            onBrush={handleBrushMove}
            onBrushEnd={handleBrushEnd}
          />
        </svg>
      </div>
      }
    </>
  )
}

const operators = [
  'between', 'not between', '=', '!=',
  '<', '<=',
  '>', '>='
]

/** Get options for numeric filter operators */
function OperatorMenu({ operator, updateOperator }) {
  const widthsByOperator = {
    'between': 75,
    'not between': 100,
    '=': 50,
    '!=': 50,
    '<': 50,
    '<=': 50,
    '>': 50,
    '>=': 50
  }
  const menuWidth = `${widthsByOperator[operator] }px`
  return (
    <select
      className="cell-facet-numeric-operator-menu"
      style={{ width: menuWidth }}
      value={operator}
      onChange={event => {updateOperator(event)}}
    >
      {operators.map((operator, i) => {
        return (
          <option value={operator} key={i}>{operator}</option>
        )
      })}
    </select>
  )
}

/** A visually economical input field for numeric query builder */
function NumericQueryInput({ value, border, updateInputValue, facet, filterName, style }) {
  if (border) {
    style.border = `1px solid ${border}`
  }

  return (
    <input
      type="text"
      className="numeric-query-input"
      data-analytics-name={`${facet.annotation}:${filterName}`}
      name={`${facet.annotation}:${filterName}`}
      style={style}
      value={value}
      onChange={event => {
        updateInputValue(event)
      }}
    />
  )
}

/** Assemble and propagate numeric cell filter change */
function updateNumericFilter(operator, inputValue, inputValue2, includeNa, facet, handleNumericChange) {
  const filterParam = packSelection(operator, inputValue, inputValue2, includeNa)
  handleNumericChange(facet.annotation, filterParam)
}

/** Enables manual input of numbers, by which cells get filtered */
function NumericQueryBuilder({
  facet, operator, inputValue, inputValue2, includeNa, inputBorder, inputBorder2, hasNull,
  precision,
  updateOperator, updateInputValue, updateIncludeNa
}) {
  const styles = getResponsiveStyles(inputValue, inputValue2, operator, precision)

  return (
    <div className="cell-facet-numeric-query-builder">
      <OperatorMenu
        operator={operator}
        updateOperator={updateOperator}
      />
      <div className="cell-facet-numeric-inputs-container">
        <NumericQueryInput
          value={inputValue}
          border={inputBorder}
          updateInputValue={updateInputValue}
          facet={facet}
          style={styles.input}
          filterName="value"
        />
        {['between', 'not between'].includes(operator) &&
      <>
        <span style={styles.and}>and</span>
        <NumericQueryInput
          value={inputValue2}
          border={inputBorder2}
          updateInputValue={updateInputValue}
          facet={facet}
          style={styles.input2}
          filterName="value2"
        />
      </>
        }
      </div>
      {hasNull &&
      <div>
        <label className="cell-filter-label" style={{ fontWeight: 'normal' }}>
          <input
            type="checkbox"
            className="numeric-na-filter"
            checked={includeNa}
            onChange={updateIncludeNa}
            style={{ marginRight: '5px' }}
          />N/A</label>
      </div>
      }
    </div>
  )
}

/** Get D3 scale to convert between numeric annotation values and pixels */
function getXScale(bars, histogramWidth, hasNull) {
  const barStartIndex = hasNull ? 2 : 0
  const valueDomain = []
  const pxRange = []
  for (let i = barStartIndex; i < bars.length; i++) {
    const bar = bars[i]
    valueDomain.push(bar.start)
    const x = bar.x + (hasNull ? 0 : SLIDER_HANDLEBAR_WIDTH + 2)
    pxRange.push(x)
  }
  const lastBar = bars.slice(-1)[0]
  valueDomain.push(lastBar.end)
  pxRange.push(histogramWidth + (hasNull ? 0 : SLIDER_HANDLEBAR_WIDTH))

  const xScale = scaleLinear(valueDomain, pxRange)
  return xScale
}

/** Get width and height for SVG elements for histogram */
function getHistogramSvgDimensions(bars) {
  const lastBar = bars.slice(-1)[0]
  const histogramWidth = lastBar.x + lastBar.width
  const histogramHeight = HISTOGRAM_BAR_MAX_HEIGHT + 2
  return [histogramWidth, histogramHeight]
}

/**
 * Get width and font size for input, to help keep full value glanceable
 */
function getInputStyle(inputValue, operator, precision) {
  let width = 37
  let fontSize = 13

  const roundedNumber = round(inputValue, precision)
  const stringValue = roundedNumber.toString()
  let numDigits = stringValue.length
  if (stringValue.includes('.')) {numDigits -= 0.75}

  if (
    numDigits > 4 &&
        (!['between', 'not between'].includes(operator) || numDigits <= 7)
  ) {
    fontSize = 12
    width += 6 * (numDigits - 4)
  } else if (numDigits > 7) {
    fontSize = 11
    width += 5.5 * (numDigits - 4)
  }

  const style = {
    width: `${width}px`,
    fontSize: `${fontSize}px`,
    numDigits // Not a standard style, but a helpful prop
  }

  return style
}

/** Make big input numbers fit on one more more often */
function getResponsiveStyles(inputValue, inputValue2, operator, precision) {
  const inputStyle = getInputStyle(inputValue, operator, precision)
  const inputStyle2 = getInputStyle(inputValue2, operator, precision)
  const andStyle = { marginLeft: '4px' }
  const totalDigits = inputStyle.numDigits + inputStyle2.numDigits
  if (totalDigits > 14) {
    andStyle.marginLeft = '2px'
    andStyle.marginRight = '-2px'
    if (totalDigits > 16) {andStyle.fontSize = 11.5}
  }
  const styles = {
    input: inputStyle,
    input2: inputStyle2,
    and: andStyle
  }
  return styles
}

/**
 * Convert nested array to flat list of params for a numeric filter selection
 *
 * E.g. [['between', [20, 40]], true]
 * or more generally: [[<operator>, [<inputValue>, <inputValue2>]], <includeNa>]
 */
function unpackSelection(selection) {
  const numericFilter = selection[0] // e.g. ['between', [20, 40]]
  const rawOp = numericFilter[0][0] // e.g. 'between'
  let raw1; let raw2
  if (['between', 'not between'].includes(rawOp)) {
    [raw1, raw2] = numericFilter[0][1] // e.g. 20, 40
  } else {
    raw1 = numericFilter[0][1]
    raw2 = null
  }
  const rawIncludeNa = selection[1] // e.g. true
  return [rawOp, raw1, raw2, rawIncludeNa]
}

/** Convert flat list of params to nested array for a numeric filter selection */
function packSelection(operator, inputValue, inputValue2, includeNa) {
  let value
  if (['between', 'not between'].includes(operator)) {
    value = [inputValue, inputValue2]
  } else {
    value = inputValue
  }
  const filterParam = [[[operator, value]], includeNa]
  return filterParam
}

/** Return new values from D3 brush selection */
function parseValuesFromBrushSelection(brushSelection, xScale, precision) {
  const extent = brushSelection.map(xScale.invert)
  const newValue1 = round(extent[0], precision)
  const newValue2 = round(extent[1], precision)
  return [newValue1, newValue2]
}

/** Determine if this numeric facet has a non-default selection */
function getNumericHasNondefaultSelection(facet, selection) {
  const defaultSelection = facet.defaultSelection
  const numericHasNondefaultSelection = !_isEqual(selection.toString(), defaultSelection.toString())
  return numericHasNondefaultSelection
}

/** Convert SVGBrush event's 2D selection array to D3's 1D selection array */
function get1DBrushSelection(brushEvent) {
  if (brushEvent.selection === null) {return null}
  return [brushEvent.selection[0][0], brushEvent.selection[1][0]]
}

/** Return whether value or not a number, roughly */
function isRoughNaN(value) {
  return isNaN(value) || value === ' '
}

/** Cell filter component for continuous numeric annotation dimension */
export function NumericCellFacet({
  facet, filters, selection, selectionMap, handleNumericChange,
  isFullyCollapsed, setIsFullyCollapsed
}) {
  const [operator, raw1, raw2, includeNa] = unpackSelection(selection)
  const [inputValue, setInputValue] = useState(raw1) // e.g. 20
  const [inputValue2, setInputValue2] = useState(raw2) // e.g. 40

  // These help indicate invalid manual input, e.g. > max, < min, non-numbers
  const [inputBorder, setInputBorder] = useState(null)
  const [inputBorder2, setInputBorder2] = useState(null)

  const [min, max, hasNull] = getMinMaxValues(filters)
  const bars = getHistogramBars(filters)
  const [histogramWidth, histogramHeight] = getHistogramSvgDimensions(bars)

  // Enables converting numeric annotation values to pixels, and vice versa
  const xScale = getXScale(bars, histogramWidth, hasNull)

  // Current range of the slider, in pixels
  const [brushSelection, setBrushSelection] = useState([inputValue, inputValue2].map(xScale))

  const packedSelection = packSelection(operator, inputValue, inputValue2, includeNa)
  const numericHasNondefaultSelection = getNumericHasNondefaultSelection(facet, packedSelection)

  useEffect(() => {
    updateInputBorders(inputValue, inputValue2)

    let [trimmedValue, trimmedValue2] = [inputValue, inputValue2]
    if (inputValue < min) {trimmedValue = min}
    if (inputValue2 > max) {trimmedValue2 = max}
    setBrushSelection([trimmedValue, trimmedValue2].map(xScale))
  }, [inputValue, inputValue2])


  useEffect(() => {
    if (raw1 !== '') {setInputValue(raw1)}
    if (raw2 !== '') {setInputValue2(raw2)}
  }, [selection.toString()])

  /** Propagate manual changes to numeric input UI fields */
  function updateInputValue(event) {
    const rawValue = event.target.value
    let newFilterValue
    const newDisplayValue = rawValue

    const rawIsNaN = isRoughNaN(rawValue)
    if (!rawIsNaN && rawValue !== '') {
      newFilterValue = parseFloat(rawValue)
    }

    // Indicate any invalid input, and update the filter
    const isValue2 = event.target.name.endsWith('value2')
    if (isValue2) {
      if (rawIsNaN) {newFilterValue = max}
      setInputValue2(newDisplayValue)
      if (rawValue !== '') {
        if (newFilterValue < min || newFilterValue > max) {
          setInputBorder2('orange')
        } else {
          setInputBorder2(rawIsNaN ? 'red' : null)
          updateNumericFilter(operator, inputValue, newFilterValue, includeNa, facet, handleNumericChange)
        }
      }
    } else {
      if (rawIsNaN) {newFilterValue = min}
      if (rawValue !== '') {setInputValue(newDisplayValue)}
      if (newFilterValue < min || newFilterValue > max) {
        setInputBorder('orange')
      } else {
        setInputBorder(rawIsNaN ? 'red' : null)
        updateNumericFilter(operator, newFilterValue, inputValue2, includeNa, facet, handleNumericChange)
      }
    }
  }

  /** Propagate change in operator selected from menu locally and upstream */
  function updateOperator(event) {
    const newOperator = event.target.value

    let newInputValue2 = inputValue2
    if (['between', 'not between'].includes(newOperator) && inputValue2 === null) {
      // If switching from operator "=" to e.g. "between", then we need to
      // ensure the 2nd input value -- which was `null` for "=" -- is set
      // to some valid value for the range expected by "between".
      const defaultInputValue2 = unpackSelection(facet.defaultSelection)[2]
      newInputValue2 = defaultInputValue2
    }
    updateNumericFilter(newOperator, inputValue, newInputValue2, includeNa, facet, handleNumericChange)
  }

  /** Propagate change in "N/A" checkbox locally and upstream */
  function updateIncludeNa() {
    updateNumericFilter(operator, inputValue, inputValue2, !includeNa, facet, handleNumericChange)
  }

  // Numeric annotations don't specify whether they are integers or floats.
  // Inferring integers gives slider expected behavior for non-floats, and saves UI space.
  const isLikelyAllIntegers = Number.isInteger(min) && Number.isInteger(max)
  const precision = isLikelyAllIntegers ? 0 : 2 // Round to integer, or 2 decimal places

  /** Clear any warning / error state from inputs if warranted */
  function updateInputBorders(newValue, newValue2) {
    if (inputBorder !== null && newValue <= max && newValue >= min) {
      setInputBorder(null)
    }
    if (inputBorder2 !== null && newValue2 <= max && newValue2 >= min) {
      setInputBorder2(null)
    }
  }

  /** Handle slider end event (i.e., mouseup) */
  function handleBrushEnd(event) {
    const brushSelection = get1DBrushSelection(event)
    if (!brushSelection) {return}

    const [newValue, newValue2] =
      parseValuesFromBrushSelection(brushSelection, xScale, precision)

    updateNumericFilter(operator, newValue, newValue2, includeNa, facet, handleNumericChange)

    updateInputBorders(newValue, newValue2)
  }

  /** Handle slider move event (i.e., drag or resize) */
  function handleBrushMove(event) {
    const brushSelection = get1DBrushSelection(event)
    if (!brushSelection) {return}

    const [newValue, newValue2] =
      parseValuesFromBrushSelection(brushSelection, xScale, precision)

    if (
      newValue > max || newValue < min || newValue2 > max || newValue2 < min ||
      Number.isNaN(newValue) || Number.isNaN(newValue2)
    ) {
      // Prevent handlebar misdisplay if crosshair-select moves out-of-bounds
      // See "overshot_slider.mov"
      // in https://github.com/broadinstitute/single_cell_portal_core/pull/1988#pullrequestreview-1920037002
      return
    }

    if (setBrushSelection) {
      // Update slider position but not filter while moving slider
      setBrushSelection(brushSelection)
    }

    if (setInputValue) {
      // Update UI input fields but not filter while moving slider
      setInputValue(newValue)
      setInputValue2(newValue2)
    }
  }

  /** Reset numeric facet to default values, i.e. clear facet */
  function handleResetFacet(facet) {
    const defaultSelection = facet.defaultSelection
    const [defOp, def, def2, defIncludeNa] = unpackSelection(defaultSelection)
    setInputBorder(null)
    setInputBorder2(null)
    updateNumericFilter(defOp, def, def2, defIncludeNa, facet, handleNumericChange)
  }

  return (
    <>
      <FacetHeader
        facet={facet}
        selectionMap={selectionMap}
        isFullyCollapsed={isFullyCollapsed}
        setIsFullyCollapsed={setIsFullyCollapsed}
        handleResetFacet={handleResetFacet}
        numericHasNondefaultSelection={numericHasNondefaultSelection}
      />
      {!isFullyCollapsed &&
      <div style={{ marginLeft: 20, position: 'relative' }}>
        <Histogram
          facet={facet}
          filters={filters}
          bars={bars}
          histogramWidth={histogramWidth}
          histogramHeight={histogramHeight}
          operator={operator}
          brushSelection={brushSelection}
          handleBrushMove={handleBrushMove}
          handleBrushEnd={handleBrushEnd}
        />
        <NumericQueryBuilder
          facet={facet}
          operator={operator}
          inputValue={inputValue}
          inputValue2={inputValue2}
          includeNa={includeNa}
          inputBorder={inputBorder}
          inputBorder2={inputBorder2}
          precision={precision}
          hasNull={hasNull}
          updateOperator={updateOperator}
          updateInputValue={updateInputValue}
          updateIncludeNa={updateIncludeNa}
        />
      </div>
      }
    </>
  )
}
