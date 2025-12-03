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
      if (!this.rowMetadata.size) {
        this.rowMetadata = new Map()
      }
      return {
        add: name => {
          if (!this.rowMetadata.has(name)) {
            this.rowMetadata.set(name, [])
          }
          const values = this.rowMetadata.get(name)
          return {
            setValue: (index, value) => {
              values[index] = value
            },
            getValue: index => values[index]
          }
        },
        getValue: (index, name) => {
          return this.rowMetadata.get(name)?.[index]
        }
      }
    }

    getColumnMetadata() {
      if (!this.columnMetadata.size) {
        this.columnMetadata = new Map()
      }
      return {
        add: name => {
          if (!this.columnMetadata.has(name)) {
            this.columnMetadata.set(name, [])
          }
          const values = this.columnMetadata.get(name)
          return {
            setValue: (index, value) => {
              values[index] = value
            },
            getValue: index => values[index]
          }
        },
        getValue: (index, name) => {
          return this.columnMetadata.get(name)?.[index]
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

      // CD3D has 0 expression in Monocytes
      // Columns are sorted alphabetically: B cells(0), Monocytes(1), NK cells(2), T cells(3)
      const cd3dMonocytesValue = dataset.getValue(0, 1, 0) // series 0 = mean expression
      expect(cd3dMonocytesValue).toBeNaN()
    })

    it('preserves non-zero raw expression values', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // CD3D has 2.5 expression in T cells
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)
      const cd3dTcellsValue = dataset.getValue(0, 3, 0)
      expect(cd3dTcellsValue).toBe(2.5)
    })

    it('scales percent expressing to 0-100 range', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // CD3D has 0.95 percent expressing in T cells
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)
      const cd3dTcellsPercent = dataset.getValue(0, 3, 1) // series 1 = percent
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

      // Verify by checking expression values match expected genes
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)

      // CD3D (index 0) should have high expression in T cells
      expect(dataset.getValue(0, 3, 0)).toBe(2.5)

      // CD79A (index 1) should have high expression in B cells
      expect(dataset.getValue(1, 0, 0)).toBe(3.1)
    })

    it('sorts cell types/annotations alphabetically', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // Verify by checking that known cell type patterns are in the right columns
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)

      // B cells should have high CD79A
      expect(dataset.getValue(1, 0, 0)).toBe(3.1)

      // NK cells should have high NKG7
      expect(dataset.getValue(2, 2, 0)).toBe(2.8)

      // T cells should have high CD3D
      expect(dataset.getValue(0, 3, 0)).toBe(2.5)
    })
  })

  describe('UBC gene normalization', () => {
    it('handles UBC expression values correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      // UBC is the 4th gene (index 3)
      const ubcGeneIndex = 3
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)

      // All UBC values should be preserved as raw values
      expect(dataset.getValue(ubcGeneIndex, 0, 0)).toBe(2.081) // B cells
      expect(dataset.getValue(ubcGeneIndex, 1, 0)).toBe(3.394) // Monocytes (highest)
      expect(dataset.getValue(ubcGeneIndex, 2, 0)).toBe(2.012) // NK cells
      expect(dataset.getValue(ubcGeneIndex, 3, 0)).toBe(1.926) // T cells
    })

    it('scales UBC percent expressing correctly', () => {
      const dataset = window.createMorpheusDotPlot(PRECOMPUTED_DOT_PLOT_DATA)

      const ubcGeneIndex = 3
      // Columns sorted: B cells(0), Monocytes(1), NK cells(2), T cells(3)

      // Percent values should be scaled to 0-100
      expect(dataset.getValue(ubcGeneIndex, 0, 1)).toBeCloseTo(96.9, 1) // B cells: 0.969 * 100
      expect(dataset.getValue(ubcGeneIndex, 1, 1)).toBeCloseTo(95, 1) // Monocytes: 0.95 * 100
      expect(dataset.getValue(ubcGeneIndex, 2, 1)).toBeCloseTo(77.49, 1) // NK cells: 0.7749 * 100
      expect(dataset.getValue(ubcGeneIndex, 3, 1)).toBeCloseTo(92.37, 1) // T cells: 0.9237 * 100
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

  describe('Row and column ordering', () => {
    it('preserves gene order when provided', () => {
      const data = {
        annotation_name: 'cell_type',
        values: ['T cells', 'B cells'],
        genes: {
          'GENE_A': [[1, 0.5], [2, 0.6]],
          'GENE_B': [[3, 0.7], [4, 0.8]],
          'GENE_C': [[5, 0.9], [6, 0.95]]
        }
      }

      // Specify custom gene order
      const geneOrder = ['GENE_C', 'GENE_A', 'GENE_B']
      const dataset = window.createMorpheusDotPlot(data, geneOrder)

      expect(dataset.getRowCount()).toBe(3)

      // Check that genes are in the specified order
      const rowMetadata = dataset.getRowMetadata()
      expect(rowMetadata.getValue(0, 'id')).toBe('GENE_C')
      expect(rowMetadata.getValue(1, 'id')).toBe('GENE_A')
      expect(rowMetadata.getValue(2, 'id')).toBe('GENE_B')

      // Verify data matches the reordered genes
      // Columns: B cells(0), T cells(1)
      expect(dataset.getValue(0, 1, 0)).toBe(5) // GENE_C, T cells
      expect(dataset.getValue(1, 1, 0)).toBe(1) // GENE_A, T cells
      expect(dataset.getValue(2, 1, 0)).toBe(3) // GENE_B, T cells
    })

    it('sorts columns alphabetically with natural sort', () => {
      const data = {
        annotation_name: 'cell_type',
        values: ['Neutrophils', 'B cells', 'T cells', 'LC2', 'LC1', 'LC10'],
        genes: {
          'GENE1': [[1, 0.5], [2, 0.6], [3, 0.7], [4, 0.8], [5, 0.9], [6, 0.95]]
        }
      }

      const dataset = window.createMorpheusDotPlot(data)

      expect(dataset.getColumnCount()).toBe(6)

      // Check that columns are sorted alphabetically with natural sort (LC1, LC2, LC10)
      const colMetadata = dataset.getColumnMetadata()
      expect(colMetadata.getValue(0, 'id')).toBe('B cells')
      expect(colMetadata.getValue(1, 'id')).toBe('LC1')
      expect(colMetadata.getValue(2, 'id')).toBe('LC2')
      expect(colMetadata.getValue(3, 'id')).toBe('LC10')
      expect(colMetadata.getValue(4, 'id')).toBe('Neutrophils')
      expect(colMetadata.getValue(5, 'id')).toBe('T cells')
    })

    it('handles case-insensitive column sorting', () => {
      const data = {
        annotation_name: 'cell_type',
        values: ['dendritic cells', 'B cells', 'T cells', 'Eosinophils'],
        genes: {
          'GENE1': [[1, 0.5], [2, 0.6], [3, 0.7], [4, 0.8]]
        }
      }

      const dataset = window.createMorpheusDotPlot(data)

      expect(dataset.getColumnCount()).toBe(4)

      // Check case-insensitive alphabetical order
      const colMetadata = dataset.getColumnMetadata()
      expect(colMetadata.getValue(0, 'id')).toBe('B cells')
      expect(colMetadata.getValue(1, 'id')).toBe('dendritic cells')
      expect(colMetadata.getValue(2, 'id')).toBe('Eosinophils')
      expect(colMetadata.getValue(3, 'id')).toBe('T cells')
    })

    it('remaps data correctly when sorting columns', () => {
      const data = {
        annotation_name: 'cell_type',
        values: ['Z cells', 'A cells', 'M cells'],
        genes: {
          'GENE1': [[10, 0.1], [20, 0.2], [30, 0.3]]
        }
      }

      const dataset = window.createMorpheusDotPlot(data)

      // Columns should be sorted: A cells, M cells, Z cells
      const colMetadata = dataset.getColumnMetadata()
      expect(colMetadata.getValue(0, 'id')).toBe('A cells')
      expect(colMetadata.getValue(1, 'id')).toBe('M cells')
      expect(colMetadata.getValue(2, 'id')).toBe('Z cells')

      // Verify data is remapped correctly
      expect(dataset.getValue(0, 0, 0)).toBe(20) // A cells (was index 1)
      expect(dataset.getValue(0, 1, 0)).toBe(30) // M cells (was index 2)
      expect(dataset.getValue(0, 2, 0)).toBe(10) // Z cells (was index 0)

      // Check percent expressing is also remapped
      expect(dataset.getValue(0, 0, 1)).toBeCloseTo(20, 1) // A cells: 0.2 * 100
      expect(dataset.getValue(0, 1, 1)).toBeCloseTo(30, 1) // M cells: 0.3 * 100
      expect(dataset.getValue(0, 2, 1)).toBeCloseTo(10, 1) // Z cells: 0.1 * 100
    })
  })
})
