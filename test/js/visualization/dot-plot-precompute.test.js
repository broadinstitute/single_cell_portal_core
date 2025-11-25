import '@testing-library/jest-dom/extend-expect'

import {
  PRECOMPUTED_DOT_PLOT_DATA,
  PRECOMPUTED_WITH_ZEROS,
  PRECOMPUTED_SINGLE_CELL_TYPE,
  EXPECTED_MORPHEUS_STRUCTURE
} from './dot-plot-precompute.test-data'

// Mock window.morpheus before importing the patch
const mockMorpheus = {
  Dataset: class MockDataset {
    constructor(config) {
      this.config = config
      this.seriesNames = [config.name]
      this.seriesArrays = [[]]
      this.seriesDataTypes = [config.dataType]
      this.rows = config.rows
      this.columns = config.columns
      this._data = new Array(config.rows).fill(null).map(() =>
        new Array(config.columns).fill(null).map(() => [0, 0])
      )
      this.rowMetadata = new Map()
      this.columnMetadata = new Map()
    }

    addSeries(config) {
      this.seriesNames.push(config.name)
      this.seriesArrays.push([])
      this.seriesDataTypes.push(config.dataType)
    }

    setValue(row, col, value, seriesIndex = 0) {
      if (!this._data[row]) {
        this._data[row] = []
      }
      if (!this._data[row][col]) {
        this._data[row][col] = []
      }
      this._data[row][col][seriesIndex] = value
    }

    getValue(row, col, seriesIndex = 0) {
      return this._data[row]?.[col]?.[seriesIndex] ?? NaN
    }

    getSeriesCount() {
      return this.seriesNames.length
    }

    getName(seriesIndex) {
      return this.seriesNames[seriesIndex]
    }

    getRowCount() {
      return this.rows
    }

    getColumnCount() {
      return this.columns
    }

    getRowMetadata() {
      return {
        add: name => {
          const values = []
          return {
            setValue: (index, value) => {
              values[index] = value
            },
            getValue: index => values[index]
          }
        }
      }
    }

    getColumnMetadata() {
      return {
        add: name => {
          const values = []
          return {
            setValue: (index, value) => {
              values[index] = value
            },
            getValue: index => values[index]
          }
        }
      }
    }
  },
  // Mock JsonDatasetReader to prevent prototype errors
  JsonDatasetReader() {},
  // Mock HeatMap to prevent prototype errors
  HeatMap() {}
}

// Add prototypes
mockMorpheus.JsonDatasetReader.prototype = {
  read: jest.fn()
}
mockMorpheus.HeatMap.prototype = {}

// Setup window.morpheus before importing the patch
if (typeof window === 'undefined') {
  global.window = {}
}
window.morpheus = mockMorpheus

// Now import the patch - it will execute immediately
require('~/lib/dot-plot-precompute-patch')

describe('Dot Plot Precompute Patch', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('createMorpheusDotPlot', () => {
    it('creates a Morpheus dataset from precomputed data', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      expect(dataset).toBeDefined()
      expect(dataset.getSeriesCount()).toBe(EXPECTED_MORPHEUS_STRUCTURE.seriesCount)
      expect(dataset.getName(0)).toBe(EXPECTED_MORPHEUS_STRUCTURE.series0Name)
      expect(dataset.getName(1)).toBe(EXPECTED_MORPHEUS_STRUCTURE.series1Name)
      expect(dataset.getRowCount()).toBe(EXPECTED_MORPHEUS_STRUCTURE.rowCount)
      expect(dataset.getColumnCount()).toBe(EXPECTED_MORPHEUS_STRUCTURE.columnCount)
    })

    it('converts zeros to NaN for color scaling', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // CD3D has 0 expression in Monocytes (column 3)
      const cd3dMonocytesValue = dataset.getValue(0, 3, 0) // series 0 = mean expression
      expect(cd3dMonocytesValue).toBeNaN()
    })

    it('preserves non-zero raw expression values', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // CD3D has 2.5 expression in T cells (row 0, column 0)
      const cd3dTcellsValue = dataset.getValue(0, 0, 0)
      expect(cd3dTcellsValue).toBe(2.5)
    })

    it('scales percent expressing to 0-100 range', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // CD3D has 0.95 percent expressing in T cells
      const cd3dTcellsPercent = dataset.getValue(0, 0, 1) // series 1 = percent
      expect(cd3dTcellsPercent).toBe(95) // 0.95 * 100
    })

    it('handles all-zero genes correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_WITH_ZEROS)

      // GENE1 has all zeros
      for (let col = 0; col < 3; col++) {
        const value = dataset.getValue(0, col, 0)
        expect(value).toBeNaN()
      }
    })

    it('handles single cell type correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_SINGLE_CELL_TYPE)

      expect(dataset.getColumnCount()).toBe(1)
      expect(dataset.getRowCount()).toBe(2)

      // Should preserve the raw value
      const gene1Value = dataset.getValue(0, 0, 0)
      expect(gene1Value).toBe(2.5)
    })

    it('sets _isDotPlot flag on dataset', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      expect(dataset._isDotPlot).toBe(true)
      expect(dataset._dotPlotSizeSeries).toBe(1)
      expect(dataset._dotPlotColorSeries).toBe(0)
    })

    it('maintains gene order from input data', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // Genes should be in the order they appear in the input object
      // Verify by checking expression values match expected genes
      // CD3D (index 0) should have high expression in T cells (column 0)
      expect(dataset.getValue(0, 0, 0)).toBe(2.5)

      // CD79A (index 1) should have high expression in B cells (column 1)
      expect(dataset.getValue(1, 1, 0)).toBe(3.1)
    })

    it('preserves cell type/annotation order', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // Verify by checking that known cell type patterns are in the right columns
      // T cells (column 0) should have high CD3D
      expect(dataset.getValue(0, 0, 0)).toBe(2.5)

      // B cells (column 1) should have high CD79A
      expect(dataset.getValue(1, 1, 0)).toBe(3.1)

      // NK cells (column 2) should have high NKG7
      expect(dataset.getValue(2, 2, 0)).toBe(2.8)
    })
  })

  describe('UBC gene normalization', () => {
    it('handles UBC expression values correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // UBC is the 4th gene (index 3)
      const ubcGeneIndex = 3

      // All UBC values should be preserved as raw values
      expect(dataset.getValue(ubcGeneIndex, 0, 0)).toBe(1.926) // T cells
      expect(dataset.getValue(ubcGeneIndex, 1, 0)).toBe(2.081) // B cells
      expect(dataset.getValue(ubcGeneIndex, 2, 0)).toBe(2.012) // NK cells
      expect(dataset.getValue(ubcGeneIndex, 3, 0)).toBe(3.394) // Monocytes (highest)
    })

    it('scales UBC percent expressing correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      const ubcGeneIndex = 3

      // Percent values should be scaled to 0-100
      expect(dataset.getValue(ubcGeneIndex, 0, 1)).toBeCloseTo(92.37, 1) // 0.9237 * 100
      expect(dataset.getValue(ubcGeneIndex, 1, 1)).toBeCloseTo(96.9, 1) // 0.969 * 100
      expect(dataset.getValue(ubcGeneIndex, 2, 1)).toBeCloseTo(77.49, 1) // 0.7749 * 100
      expect(dataset.getValue(ubcGeneIndex, 3, 1)).toBeCloseTo(95, 1) // 0.95 * 100
    })
  })

  describe('Edge cases', () => {
    it('handles empty gene list', () => {
      const emptyData = {
        annotation_name: 'cell_type',
        values: ['Type A'],
        genes: {}
      }

      const dataset = window.createMorpheusDotPlot(emptyData)

      expect(dataset.getRowCount()).toBe(0)
      expect(dataset.getColumnCount()).toBe(1)
    })

    it('handles missing percent expressing values', () => {
      const dataWithMissingPercent = {
        annotation_name: 'cell_type',
        values: ['Type A', 'Type B'],
        genes: {
          'GENE1': [
            [2.5, 0.95],
            [1.5, undefined] // Missing percent
          ]
        }
      }

      const dataset = window.createMorpheusDotPlot(dataWithMissingPercent)

      // Should handle undefined gracefully
      expect(dataset.getValue(0, 0, 1)).toBe(95)
      expect(dataset.getValue(0, 1, 1)).toBeNaN()
    })
  })
})
