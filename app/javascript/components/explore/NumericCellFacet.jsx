import React, { useState, useRef, useEffect } from 'react'
import * as d3 from 'd3'

import { FacetHeader } from '~/components/explore/FacetComponents'
import { round } from '~/lib/metrics-perf'
import { getMinMaxValues } from '~/lib/cell-faceting.js'

const HISTOGRAM_BAR_MAX_HEIGHT = 20

/** Initialize D3 brush component, for draggable selections */
function initBrush(brush, sliderId) {
  const brushDom = document.querySelector(`#${sliderId} .brush`)
  if (brushDom) {brushDom.remove()}
  d3.select(`#${sliderId}`).append('g').attr('class', 'brush').call(brush)
}

function clearBrush(sliderId, brush) {
  d3.select(`#${sliderId} .brush`).call(brush.move, null)
}

/** Move D3 brush slider */
function moveBrush(sliderId, brush, value1, value2, xScale) {
  const [px1, px2] = [value1, value2].map(xScale)
  console.log('px1, px2, value1, value2', px1, px2, value1, value2)
  d3.select(`#${sliderId} .brush`).call(brush.move, [px1, px2])
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
  const numBinsNullTrimmed = hasNull ? numBins - 1 : numBins
  const binSize = (maxValue - minValue) / numBinsNullTrimmed
  let bars = []

  for (let i = 0; i < numBins; i++) {
    const isNull = hasNull && i === 0
    let start
    let end
    const indexNullTrimmed = hasNull ? i - 1 : i
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
      if (j === 0 && bar.isNull) {
        if (value === null) {
          // Count number of cells that have no numeric value for this annotation
          bars[j].count += count
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
function Histogram({ sliderId, filters, bars, brush, svgWidth, svgHeight }) {
  useEffect(() => {
    console.log('in Histogram useEffect')
    initBrush(brush, sliderId)
  },
  [filters.join(',')]
  )

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
      <svg
        height={svgHeight}
        width={svgWidth}
        style={{ position: 'absolute', top: 0, left: 0 }}
        className="numeric-filter-histogram-slider"
        id={sliderId}
      ></svg>
    </>
  )
}

const operators = [
  'between', 'not between', '=', '!=',
  '<', '<=',
  '>', '>='
]

/** Get options for numeric filter operators */
function OperatorMenu({ operator, setOperator }) {
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
      onChange={event => {setOperator(event.target.value)}}
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
  setOperator, updateInputValue, updateIncludeNa
}) {
  console.log(`in NumericQueryBuilder for ${ facet.annotation }, inputValue, inputValue2`, inputValue, inputValue2)
  return (
    <div>
      <OperatorMenu
        operator={operator}
        setOperator={setOperator}
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
        <label style={{ fontWeight: 'normal' }}>
          <input
            type="checkbox"
            className="na-filter"
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
  const barStartIndex = hasNull ? 1 : 0
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
 * Get operator and values from selection
 *
 * E.g. [['between', [20, 40]], true]
 * or more generally: [[<operator>, [<inputValue>, <inputValue2>]], <includeNa>]
 */
function parseSelectionMap(facet, selectionMap) {
  const facetSelection = selectionMap[facet.annotation] // e.g. ['between', [20, 40]]
  const numericFilter = facetSelection[0] // e.g. ['between', [20, 40]]
  const rawOp = numericFilter[0][0] // e.g. 'between'
  const [raw1, raw2] = numericFilter[0][1] // e.g. 20, 40
  const rawIncludeNa = facetSelection[1] // e.g. true
  return [rawOp, raw1, raw2, rawIncludeNa]
}

/** Cell filter component for continuous numeric annotation dimension */
export function NumericCellFacet({
  facet, filters, isChecked, selectionMap, handleNumericChange,
  hasNondefaultSelection, handleResetFacet
}) {
  const [rawOp, raw1, raw2, rawIncludeNa] = parseSelectionMap(facet, selectionMap)
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
      setInputBorder2(rawIsNaN ? 'red' : null)
      setInputValue2(newDisplayValue)
      updateNumericFilter(operator, inputValue, newFilterValue, includeNa, facet, handleNumericChange)
      moveBrush(sliderId, brush, inputValue, newFilterValue, xScale)
    } else {
      if (rawIsNaN) {newFilterValue = min}
      setInputBorder(rawIsNaN ? 'red' : null)
      setInputValue(newDisplayValue)
      updateNumericFilter(operator, newFilterValue, inputValue2, includeNa, facet, handleNumericChange)
      moveBrush(sliderId, brush, newFilterValue, inputValue2, xScale)
    }
  }

  /** Propagate change in "N/A" checkbox locally and upstream */
  function updateIncludeNa() {
    setIncludeNa(!includeNa)
    updateNumericFilter(operator, inputValue, inputValue2, !includeNa, facet, handleNumericChange)
  }

  /** Handler for the end of a brush event from D3 */
  function handleBrushEnd(event) {
    const selection = event.selection
    const extent = selection.map(xScale.invert)
    const newValue1 = round(extent[0], 2)
    const newValue2 = round(extent[1], 2)
    // setInputValue(newValue1)
    // setInputValue2(newValue2)
    updateNumericFilter(operator, newValue1, newValue2, includeNa, facet, handleNumericChange)
  }

  const [svgWidth, svgHeight] = getHistogramSvgDimensions(bars)
  const xScale = getXScale(bars, svgWidth, hasNull)
  const barWidth = bars[0].width
  const extentStartX = hasNull ? barWidth + 1 : 0

  const brush =
    d3
      .brushX()
      .extent([
        [extentStartX, 0],
        [svgWidth, svgHeight]
      ])
      .on('end', handleBrushEnd)

  const sliderId = `numeric-filter-histogram-slider___${facet.annotation}`

  console.log(`re-rendering NumericCellFacet for ${ facet.annotation}`)

  useEffect(() => {
    const [rawOp, raw1, raw2, rawIncludeNa] = parseSelectionMap(facet, selectionMap)
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
        handleResetFacet={handleResetFacet}
      />
      <div style={{ marginLeft: 20, position: 'relative' }}>
        <Histogram
          sliderId={sliderId}
          filters={filters}
          bars={bars}
          brush={brush}
          svgWidth={svgWidth}
          svgHeight={svgHeight}
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
          setOperator={setOperator}
          updateInputValue={updateInputValue}
          updateIncludeNa={updateIncludeNa}
        />
      </div>
    </>
  )
}
