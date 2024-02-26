import React, { useState, useEffect } from 'react'
import * as d3 from 'd3'

import { FacetHeader } from '~/components/explore/FacetComponents'
import { round } from '~/lib/metrics-perf'
import { getMinMaxValues } from '~/lib/cell-faceting.js'

const HISTOGRAM_BAR_MAX_HEIGHT = 20
const SLIDER_HANDLEBAR_WIDTH = 6

/**
 * Get SVG for handlebar UI, as an affordance for resizing
 *
 * Inspired by https://crossfilter.github.io/crossfilter
 */
function handlebarPath(d) {
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

/** Set slider to default pixel range, without duplicative filter update */
function setFullSlider(sliderId, brush) {
  // Get default full pixel domain for slider, e.g. [23, 179]
  const brushDom = document.querySelector(`#${sliderId} .brush`)
  if (!brushDom) {return}
  const extent = brushDom.__brush.extent
  const pxMin = extent[0][0]
  const pxMax = extent[1][0]
  const defaultPxDomain = [pxMin, pxMax]

  const brushD3Node = d3.select(`#${sliderId} .brush`)
  brushD3Node.call(brush.move, defaultPxDomain, 'skipUpdateNumericFilter')
}

/** Initialize D3 brush component, for draggable selections */
function initBrush(brush, sliderId) {
  const brushDom = document.querySelector(`#${sliderId} .brush`)
  if (brushDom) {brushDom.remove()}
  const gBrush = d3.select(`#${sliderId}`).append('g').attr('class', 'brush').call(brush)
  gBrush.selectAll('.handlebar')
    .data([{ type: 'w' }, { type: 'e' }])
    .enter().append('path')
    .attr('class', 'handlebar')
    .attr('fill', '#EEE')
    .attr('fill-opacity', 0.8)
    .attr('stroke', '#000')
    .attr('stroke-width', 0.5)
    .attr('cursor', 'ew-resize')
    .attr('d', handlebarPath)

  setFullSlider(sliderId, brush)
}

/** Reset slider for this numeric cell facet */
function clearBrush(sliderId, brush) {
  setFullSlider(sliderId, brush)
}

/** Move D3 brush slider */
function moveBrush(sliderId, brush, value1, value2, xScale) {
  const selection = [value1, value2].map(xScale)
  const [px1, px2] = selection
  d3.select(`#${sliderId} .brush`).call(brush.move, [px1, px2])
}

/** Handle move event, which is fired after brush.end */
function handleBrushMoved(sliderId, d3BrushSelection) {
  if (!d3BrushSelection) {return}
  d3.selectAll(`#${sliderId} .handlebar`)
    .attr('display', null)
    .attr('transform', (d, i) => {
      const handlebarX = d3BrushSelection[i]
      const handlebarY = -1 * (HISTOGRAM_BAR_MAX_HEIGHT - 1)
      return `translate(${ handlebarX }, ${handlebarY})`
    })
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

/** SVG histogram showing distribution of numeric annotation values */
function Histogram({ sliderId, filters, bars, brush, svgWidth, svgHeight, operator }) {
  useEffect(() => {
    initBrush(brush, sliderId)
  },
  [filters.join(','), operator]
  )

  const barWidth = bars[0].width
  const hasNull = bars[0].isNull
  const sliderLeft = hasNull ? barWidth : 1
  const sliderWidth = svgWidth + sliderLeft

  return (
    <>
      <svg
        height={svgHeight}
        width={svgWidth}
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
      <svg
        height={svgHeight}
        width={sliderWidth}
        style={{ position: 'absolute', top: 0, left: 0 }}
        className="numeric-filter-histogram-slider"
        id={sliderId}
      ></svg>
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
    'between': 80,
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
function NumericQueryInput({ value, border, updateInputValue, facet, filterName }) {
  // Visually indicate that more digits are specified than are shown
  const fadeOverflowClass = value >= 100_000 ? 'fade-overflow' : ''

  const style = border ? { border: `1px solid ${border}` } : {}

  return (
    <span className={fadeOverflowClass}>
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
    </span>
  )
}

/** Assemble and propagate numeric cell filter change */
function updateNumericFilter(operator, inputValue, inputValue2, includeNa, facet, handleNumericChange) {
  let value
  if (['between', 'not between'].includes(operator)) {
    value = [inputValue, inputValue2]
  } else {
    value = inputValue
  }
  const filterParam = [[[operator, value]], includeNa]
  handleNumericChange(facet.annotation, filterParam)
}

/** Enables manual input of numbers, by which cells get filtered */
function NumericQueryBuilder({
  facet, operator, inputValue, inputValue2, includeNa, inputBorder, inputBorder2, hasNull,
  updateOperator, updateInputValue, updateIncludeNa
}) {
  return (
    <div>
      <OperatorMenu
        operator={operator}
        updateOperator={updateOperator}
      />
      <NumericQueryInput
        value={inputValue}
        border={inputBorder}
        updateInputValue={updateInputValue}
        facet={facet}
        filterName="value"
      />
      {['between', 'not between'].includes(operator) &&
      <span>
        <span style={{ marginLeft: '4px' }}>and</span>
        <NumericQueryInput
          value={inputValue2}
          border={inputBorder2}
          updateInputValue={updateInputValue}
          facet={facet}
          filterName="value2"
        />
      </span>
      }
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
function getXScale(bars, svgWidth, hasNull) {
  const barStartIndex = hasNull ? 2 : 0
  const valueDomain = []
  const pxRange = []
  for (let i = barStartIndex; i < bars.length; i++) {
    const bar = bars[i]
    valueDomain.push(bar.start)
    pxRange.push(bar.x)
  }
  const lastBar = bars.slice(-1)[0]
  valueDomain.push(lastBar.end)
  pxRange.push(svgWidth)
  const xScale = d3.scaleLinear().domain(valueDomain).range(pxRange)
  return xScale
}

/** Get width and height for SVG elements for histogram (and slider overlay) */
function getHistogramSvgDimensions(bars) {
  const lastBar = bars.slice(-1)[0]
  const svgWidth = lastBar.x + lastBar.width
  const svgHeight = HISTOGRAM_BAR_MAX_HEIGHT + 2
  return [svgWidth, svgHeight]
}

/**
 * Convert encoded selection to operator, values, and whether to include "N/A"
 *
 * E.g. [['between', [20, 40]], true]
 * or more generally: [[<operator>, [<inputValue>, <inputValue2>]], <includeNa>]
 */
function parseSelection(selection) {
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

/** Cell filter component for continuous numeric annotation dimension */
export function NumericCellFacet({
  facet, filters, selectionMap, handleNumericChange,
  handleResetFacet, isFullyCollapsed, setIsFullyCollapsed
}) {
  const selection = selectionMap[facet.annotation] // e.g. [['between', [20, 40]], true]
  const [rawOp, raw1, raw2, rawIncludeNa] = parseSelection(selection)
  const [operator, setOperator] = useState(rawOp) // e.g. 'between'
  const [inputValue, setInputValue] = useState(raw1) // e.g. 20
  const [inputBorder, setInputBorder] = useState(null)
  const [inputValue2, setInputValue2] = useState(raw2) // e.g. 40
  const [inputBorder2, setInputBorder2] = useState(null)

  const [min, max, hasNull] = getMinMaxValues(filters)

  const bars = getHistogramBars(filters)

  // Whether to include cells with "not available" (N/A, `null`) numeric value
  const [includeNa, setIncludeNa] = useState(rawIncludeNa) // e.g. true

  /** Propagate change in numeric input locally and upstream */
  function updateInputValue(event) {
    const rawValue = event.target.value
    let newFilterValue
    const newDisplayValue = rawValue

    const rawIsNaN = isNaN(rawValue) || rawValue === '' || rawValue === ' '
    if (!rawIsNaN) {
      newFilterValue = parseFloat(rawValue)
    }

    const isValue2 = event.target.name.endsWith('value2')
    if (isValue2) {
      if (rawIsNaN) {newFilterValue = max}
      setInputValue2(newDisplayValue)
      if (newFilterValue > max) {
        setInputBorder2('orange')
      } else {
        setInputBorder2(rawIsNaN ? 'red' : null)
        updateNumericFilter(operator, inputValue, newFilterValue, includeNa, facet, handleNumericChange)
        moveBrush(sliderId, brush, inputValue, newFilterValue, xScale)
      }
    } else {
      if (rawIsNaN) {newFilterValue = min}
      setInputValue(newDisplayValue)
      if (newFilterValue < min) {
        setInputBorder('orange')
      } else {
        setInputBorder(rawIsNaN ? 'red' : null)
        updateNumericFilter(operator, newFilterValue, inputValue2, includeNa, facet, handleNumericChange)
        moveBrush(sliderId, brush, newFilterValue, inputValue2, xScale)
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
      const defaultInputValue2 = parseSelection(facet.defaultSelection)[2]
      newInputValue2 = defaultInputValue2
    }
    updateNumericFilter(newOperator, inputValue, newInputValue2, includeNa, facet, handleNumericChange)
    setOperator(newOperator)
    setInputValue2(newInputValue2)
  }

  /** Propagate change in "N/A" checkbox locally and upstream */
  function updateIncludeNa() {
    setIncludeNa(!includeNa)
    updateNumericFilter(operator, inputValue, inputValue2, !includeNa, facet, handleNumericChange)
  }

  const isLikelyAllIntegers = Number.isInteger(min) && Number.isInteger(max)
  const precision = isLikelyAllIntegers ? 0 : 2 // Round to integer, or 2 decimal places

  /** Handler for the end of a brush event from D3 */
  function handleBrushEnd(event) {
    const d3BrushSelection = event.selection
    const extent = d3BrushSelection.map(xScale.invert)
    const newValue1 = round(extent[0], precision)
    const newValue2 = round(extent[1], precision)

    handleBrushMoved(sliderId, d3BrushSelection)
    if (event.sourceEvent !== 'skipUpdateNumericFilter') {
      updateNumericFilter(operator, newValue1, newValue2, includeNa, facet, handleNumericChange)
    }

    if (inputBorder !== null && newValue1 >= min) {
      console.log('setInputBorder(null)')
      setInputBorder(null)
    }
    if (inputBorder2 !== null && newValue2 <= max) {
      console.log('setInputBorder2(null)')
      setInputBorder2(null)
    }
  }

  const [svgWidth, svgHeight] = getHistogramSvgDimensions(bars)
  const xScale = getXScale(bars, svgWidth, hasNull)
  const barWidth = bars[0].width
  const extentStartX = hasNull ? 2 * barWidth + 2 : 0

  const brush =
    d3
      .brushX()
      .extent([
        [extentStartX, 0],
        [svgWidth, svgHeight]
      ])
      .on('end', handleBrushEnd)
      .on('brush', event => {
        const d3BrushSelection = event.selection
        handleBrushMoved(sliderId, d3BrushSelection)
      })

  const sliderId = `numeric-filter-histogram-slider___${facet.annotation}`

  // console.log(`re-rendering NumericCellFacet for ${ facet.annotation}`)

  useEffect(() => {
    const selection = selectionMap[facet.annotation]
    const [rawOp, raw1, raw2, rawIncludeNa] = parseSelection(selection)
    setOperator(rawOp)
    setInputValue(raw1)
    setInputValue2(raw2)
    setIncludeNa(rawIncludeNa)
  }, [Object.values(selectionMap).join(',')])

  return (
    <>
      <FacetHeader
        facet={facet}
        selectionMap={selectionMap}
        isFullyCollapsed={isFullyCollapsed}
        setIsFullyCollapsed={setIsFullyCollapsed}
        handleResetFacet={handleResetFacet}
        clearBrush={clearBrush}
        sliderId={sliderId}
        brush={brush}
      />
      {!isFullyCollapsed &&
      <div style={{ marginLeft: 20, position: 'relative' }}>
        <Histogram
          sliderId={sliderId}
          filters={filters}
          bars={bars}
          brush={brush}
          svgWidth={svgWidth}
          svgHeight={svgHeight}
          operator={operator}
        />
        <NumericQueryBuilder
          facet={facet}
          operator={operator}
          inputValue={inputValue}
          inputValue2={inputValue2}
          includeNa={includeNa}
          inputBorder={inputBorder}
          inputBorder2={inputBorder2}
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
