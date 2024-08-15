import PlotUtils, { safenLabels } from 'lib/plot'

describe('Plot grouping function cache', () => {
  it('makes traces based on the annotation groups', async () => {
    const data = {
      x: [1, 2, 3, 4, 5],
      y: [4, 5, 6, 7, 8],
      annotations: ['a', 'b', 'c', 'a', 'b'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5']
    }

    const [traces, countsByLabel] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true })
    expect(traces).toHaveLength(3)
    expect(traces[0]).toEqual({
      x: [1, 4],
      y: [4, 7],
      annotations: ['a', 'a'],
      cells: ['c1', 'c4'],
      name: 'a',
      visible: true
    })
    expect(traces[1]).toEqual({
      x: [2, 5],
      y: [5, 8],
      annotations: ['b', 'b'],
      cells: ['c2', 'c5'],
      name: 'b',
      visible: true
    })
    expect(traces[2]).toEqual({
      x: [3],
      y: [6],
      annotations: ['c'],
      cells: ['c3'],
      name: 'c',
      visible: true
    })

    expect(countsByLabel).toEqual({ a: 2, b: 2, c: 1 })
  })

  it('sorts traces based on number of points', async () => {
    const data = {
      x: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
      y: [4, 5, 6, 7, 8, 7, 8, 9, 0, 1],
      annotations: ['a', 'd', 'c', 'a', 'b', 'd', 'd', 'd', 'b', 'a'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10']
    }

    const [traces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true })
    expect(traces).toHaveLength(4)
    expect(traces.map(t => t.name)).toEqual(['d', 'a', 'b', 'c'])
  })

  it('puts the active annotation as the last trace', async () => {
    const data = {
      x: [1, 2, 3, 4, 5],
      y: [4, 5, 6, 7, 8],
      annotations: ['a', 'b', 'c', 'a', 'b'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5']
    }

    const [traces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true })
    expect(traces[2].name).toEqual('c')
    const [traces2] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, activeTraceLabel: 'b' })
    expect(traces2[2].name).toEqual('b')
    const [traces3] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, activeTraceLabel: 'a' })
    expect(traces3[2].name).toEqual('a')
  })

  it('puts unspecified annotations as the first plotted trace', async () => {
    const data = {
      x: [1, 2, 3, 4, 5, 6],
      y: [4, 5, 6, 7, 8, 9],
      annotations: ['a', '--Unspecified--', 'c', 'a', '--Unspecified--', 'a'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5', 'c6']
    }

    const [traces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true })
    expect(traces.map(t => t.name)).toEqual(['--Unspecified--', 'a', 'c'])
  })

  it('puts unspecified annotations as the last legend trace', async () => {
    const sortedLabels = PlotUtils.getLegendSortedLabels({ 'a': 12, '--Unspecified--': 5, 'b': 6, 'z': 20 })
    expect(sortedLabels).toEqual(['a', 'b', 'z', '--Unspecified--'])
  })

  it('hides traces by name', async () => {
    const data = {
      x: [1, 2, 3, 4, 5],
      y: [4, 5, 6, 7, 8],
      annotations: ['a', 'b', 'c', 'a', 'b'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5']
    }

    const [allTraces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, hiddenTraces: [] })
    expect(allTraces.find(t => t.name === 'a').cells).toHaveLength(2)
    expect(allTraces.find(t => t.name === 'a').visible).toEqual(true)

    const [traces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, hiddenTraces: ['a'] })
    expect(traces.find(t => t.name === 'a').cells).toHaveLength(2)
    expect(['a', 'b', 'c'].map(name => traces.find(t => t.name === name).visible)).toEqual(['legendonly', true, true])

    const [traces2] = PlotUtils.filterTrace({
      trace: data, groupByAnnotation: true, hiddenTraces: ['a'], activeTraceLabel: 'b'
    })
    expect(traces2.map(t => t.name)).toEqual(['a', 'c', 'b'])

    const [traces3] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, hiddenTraces: ['b', 'c'] })
    expect(['a', 'b', 'c'].map(name => traces3.find(t => t.name === name).visible)).toEqual([true, 'legendonly', 'legendonly'])

    const [traces4] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: true, hiddenTraces: ['b', 'c', 'a'] })
    expect(['a', 'b', 'c'].map(name => traces4.find(t => t.name === name).visible)).toEqual(['legendonly', 'legendonly', 'legendonly'])
  })

  it('sorts expression data ', async () => {
    const data = {
      x: [1, 2, 3, 4, 5],
      y: [4, 5, 6, 7, 8],
      annotations: ['a', 'b', 'c', 'a', 'b'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5'],
      expression: [0, 4, 1, 5.5, 0]
    }

    const [traces] = PlotUtils.filterTrace({ trace: data, groupByAnnotation: false })
    expect(traces).toHaveLength(1)
    expect(traces[0].x).toEqual([1, 2, 3, 4, 5])

    const sortedTrace = PlotUtils.sortTraceByExpression(traces[0])
    expect(sortedTrace).toEqual({
      x: [1, 5, 3, 2, 4],
      y: [4, 8, 6, 5, 7],
      annotations: ['a', 'b', 'c', 'b', 'a'],
      cells: ['c1', 'c5', 'c3', 'c2', 'c4'],
      expression: [0, 0, 1, 4, 5.5]
    })
  })

  it('filters on expression data ', async () => {
    const data = {
      x: [1, 2, 3, 4, 5],
      y: [4, 5, 6, 7, 8],
      annotations: ['a', 'b', 'c', 'a', 'b'],
      cells: ['c1', 'c2', 'c3', 'c4', 'c5'],
      expression: [0, 4, 1, 5.5, 0]
    }

    const [traces] = PlotUtils.filterTrace({
      trace: data, groupByAnnotation: false, expressionData: data.expression, expressionFilter: [0.5, 1]
    })
    expect(traces[0]).toEqual({
      x: [2, 4],
      y: [5, 7],
      annotations: ['b', 'a'],
      cells: ['c2', 'c4'],
      expression: [4, 5.5],
      name: 'main',
      visible: true
    })

    const [trace2] = PlotUtils.filterTrace({
      trace: data, groupByAnnotation: false, expressionData: data.expression, expressionFilter: [0, 1]
    })
    expect(trace2[0]).toEqual({
      ...data
    })
  })

  it('does not error when raw labels are undefined', async () => {
    // This prevents erroring gene expression scatter plots up applying a legend filter
    const safeLabels = safenLabels(undefined)
    expect(safeLabels).toBeUndefined()
  })
})
