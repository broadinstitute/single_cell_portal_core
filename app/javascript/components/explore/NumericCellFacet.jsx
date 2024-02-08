import React, { useState } from 'react'

import { round } from '~/lib/metrics-perf'

/** Get minimum and maximum bounds of value range for numeric filters */
function getMinMaxValues(filters) {
  const firstValue = filters[0][0]
  const hasNull = firstValue === null
  const minValue = hasNull ? filters[1][0] : firstValue
  const maxValue = filters.slice(-1)[0][0]
  return [minValue, maxValue, hasNull]
}

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
function NumericQueryInput({ value, updateInputValue, facet, filterName }) {
  const fadeOverflowClass = value >= 100_000 ? 'fade-overflow' : ''

  return (
    <span className={fadeOverflowClass}>
      <input
        type="text"
        className="numeric-query-input"
        data-analytics-name={`${facet.annotation}:${filterName}`}
        name={`${facet.annotation}:${filterName}`}
        value={value}
        onChange={event => {
          updateInputValue(event)
        }}
      />
    </span>
  )
}

/** Get raw numeric value for numeric filter, given operator */
function getFilterValue(operator, value1, value2) {
  let filterValue
  if (['between', 'not between'].includes(operator)) {
    filterValue = [value1, value2]
  } else {
    filterValue = value1
  }
  return filterValue
}


/** Enables manual input of numbers, by which cells get filtered */
function NumericQueryBuilder({ filters, handleNumericChange, facet }) {
  // console.log('in NumericQueryBuilder, filters', filters)
  const [operator, setOperator] = useState('between')
  const [minValue, maxValue] = getMinMaxValues(filters)

  const [inputValue, setInputValue] = useState(minValue)
  const [inputValue2, setInputValue2] = useState(maxValue)

  // Whether to include cells with "not available" (N/A, `null`) numeric value
  const [includeNa, setIncludeNa] = useState(true)

  /** Propagate change upstream */
  function updateNumericFilter() {
    let value
    if (['between', 'not between'].includes(operator)) {
      value = [inputValue, inputValue2]
    } else {
      value = inputValue
    }
    const filterParam = [[operator, value], includeNa]
    handleNumericChange(facet.annotation, filterParam)
  }

  /** Propagate change in numeric input locally and upstream */
  function updateInputValue(event) {
    const newValue = parseFloat(event.target.value)
    const isValue2 = parseFloat(event.target.name.endsWith('value2'))
    if (isValue2) {
      setInputValue2(newValue)
    } else {
      setInputValue(newValue)
    }

    updateNumericFilter()
  }

  /** Propagate change in "N/A" checkbox locally and upstream */
  function updateIncludeNa() {
    setIncludeNa(!includeNa)

    updateNumericFilter()
  }

  return (
    <div>
      <OperatorMenu
        operator={operator}
        setOperator={setOperator}
      />
      <NumericQueryInput
        value={inputValue}
        updateInputValue={updateInputValue}
        facet={facet}
        filterName="value"
      />
      {['between', 'not between'].includes(operator) &&
      <span>
        <span style={{ marginLeft: '4px' }}>and</span>
        <NumericQueryInput
          value={inputValue2}
          updateInputValue={updateInputValue}
          facet={facet}
          filterName="value2"
        />
      </span>
      }
      <div>
        <label
          style={{ fontWeight: 'normal' }}
          data-toggle="tooltip"
          data-placement="right"
          data-original-title="Not available"
        >
          <input
            type="checkbox"
            checked={includeNa}
            onChange={() => {updateIncludeNa()}}
          /> N/A</label>
      </div>
    </div>
  )
}

/** Cell filter component for continuous numeric annotation dimension */
export function NumericCellFacet({
  facet, filters, isChecked, checkedMap, handleNumericChange,
  hasNondefaultSelection
}) {
  // console.log('in NumericCellFacet, facet', facet)
  // console.log('in NumericCellFacet, filters', filters)

  return (
    <div style={{ marginLeft: 20, position: 'relative' }}>
      <Histogram filters={filters} />
      <NumericQueryBuilder
        filters={filters}
        handleNumericChange={handleNumericChange}
        facet={facet}
      />
    </div>
  )
}
