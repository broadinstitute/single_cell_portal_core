import React, { useState } from 'react'

import { round } from '~/lib/metrics-perf'
import { getMinMaxValues } from '~/lib/cell-faceting.js'

/** Get histogram to show with numeric filter */
function getHistogramBars(filters) {
  const [minValue, maxValue, hasNull] = getMinMaxValues(filters)

  const numBins = 15
  const numBinsNullTrimmed = hasNull ? numBins - 1 : numBins
  const binSize = (maxValue - minValue) / numBinsNullTrimmed
  const bars = []

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

  return [bars, maxValue, maxCount]
}

/** SVG histogram showing distribution of numeric annotation values */
function Histogram({ filters }) {
  const maxHeight = 20

  const [bars, maxValue, maxCount, minValue] = getHistogramBars(filters)

  const barRectAttrs = []
  bars.forEach((bar, i) => {
    const height = maxHeight * (bar.count / maxCount)
    const width = 11
    const attrs = {
      x: (width + 1) * i,
      y: maxHeight - height + 1,
      width,
      height,
      color: (bar.isNull) ? '#888' : '#3D5A87',
      bar
    }
    barRectAttrs.push(attrs)
  })

  const lastBar = barRectAttrs.slice(-1)[0]
  const svgHeight = maxHeight + 2
  const svgWidth = lastBar.x + lastBar.width
  return (
    <>
      <svg
        height={svgHeight}
        width={svgWidth}
        style={{ borderBottom: '1px solid #AAA  ' }}
        className="numeric-filter-histogram"
      >
        {barRectAttrs.map((attrs, i) => {
          return (
            <rect
              fill={attrs.color}
              x={attrs.x}
              y={attrs.y}
              width={attrs.width}
              height={attrs.height}
              key={i}
            />
          )
        })}
      </svg>
      <div style={{ position: 'absolute', top: 0 }} key={2}>
        {barRectAttrs.map((attrs, i) => {
          const bar = attrs.bar
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
                width: attrs.width + 1,
                height: maxHeight
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
    </>
  )
}

const operators = [
  'between', 'not between', 'equals', 'not equals',
  'less than', 'less than or equal to',
  'greater than', 'greater than or equal to'
]

/** Get options for numeric filter operators */
function OperatorMenu({ operator, setOperator }) {
  const widthsByOperator = {
    'between': 80,
    'not between': 100,
    'equals': 65,
    'not equals': 90,
    'less than': 80,
    'less than or equal to': 150,
    'greater than': 100,
    'greater than or equal to': 170
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

/** Assembly and propagate numeric cell filter change */
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
function NumericQueryBuilder({ selectionMap, filters, handleNumericChange, facet }) {
  // E.g. [['between', [20, 40]], true]
  // or more generally: [[<operator>, [<inputValue>, <inputValue2>]], <includeNa>]
  const facetSelection = selectionMap[facet.annotation]

  const numericFilter = facetSelection[0] // e.g. ['between', [20, 40]]
  const [operator, setOperator] = useState(numericFilter[0][0]) // e.g. 'between'
  const [inputValue, setInputValue] = useState(numericFilter[0][1][0]) // e.g. 20
  const [inputBorder, setInputBorder] = useState(null)
  const [inputValue2, setInputValue2] = useState(numericFilter[0][1][1]) // e.g. 40
  const [inputBorder2, setInputBorder2] = useState(null)

  // Whether to include cells with "not available" (N/A, `null`) numeric value
  const [includeNa, setIncludeNa] = useState(facetSelection[1]) // e.g. true

  /** Propagate change in numeric input locally and upstream */
  function updateInputValue(event) {
    const rawValue = event.target.value
    let newFilterValue
    const newDisplayValue = rawValue

    let min; let max
    const rawIsNaN = isNaN(rawValue) || rawValue === '' || rawValue === ' '
    if (rawIsNaN) {
      [min, max] = getMinMaxValues(filters)
    } else {
      newFilterValue = parseFloat(rawValue)
    }

    const isValue2 = event.target.name.endsWith('value2')
    if (isValue2) {
      if (rawIsNaN) {newFilterValue = max}
      setInputBorder2(rawIsNaN ? 'red' : null)
      setInputValue2(newDisplayValue)
      updateNumericFilter(operator, inputValue, newFilterValue, includeNa, facet, handleNumericChange)
    } else {
      if (rawIsNaN) {newFilterValue = min}
      setInputBorder(rawIsNaN ? 'red' : null)
      setInputValue(newDisplayValue)
      updateNumericFilter(operator, newFilterValue, inputValue2, includeNa, facet, handleNumericChange)
    }
  }

  /** Propagate change in "N/A" checkbox locally and upstream */
  function updateIncludeNa() {
    setIncludeNa(!includeNa)
    updateNumericFilter(operator, inputValue, inputValue2, !includeNa, facet, handleNumericChange)
  }

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
    </div>
  )
}

/** Cell filter component for continuous numeric annotation dimension */
export function NumericCellFacet({
  facet, filters, isChecked, selectionMap, handleNumericChange,
  hasNondefaultSelection
}) {
  return (
    <div style={{ marginLeft: 20, position: 'relative' }}>
      <Histogram filters={filters} />
      <NumericQueryBuilder
        selectionMap={selectionMap}
        filters={filters}
        handleNumericChange={handleNumericChange}
        facet={facet}
      />
    </div>
  )
}
