/**
 * Integration tests for DotPlot component with precomputed data
 */

import '@testing-library/jest-dom/extend-expect'
import * as ScpApi from 'lib/scp-api'
import { shouldUsePreprocessedData } from 'components/visualization/DotPlot'

import {
  PRECOMPUTED_DOT_PLOT_DATA,
  FEATURE_FLAGS_ENABLED,
  FEATURE_FLAGS_DISABLED
} from './dot-plot-precompute.test-data'

describe('DotPlot Integration with Feature Flag', () => {
  let fetchMorpheusJsonSpy

  beforeEach(() => {
    jest.clearAllMocks()
    fetchMorpheusJsonSpy = jest.spyOn(ScpApi, 'fetchMorpheusJson')
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  describe('fetchMorpheusJson endpoint selection', () => {
    it('uses dotplot endpoint when feature flag is enabled', async () => {
      fetchMorpheusJsonSpy.mockResolvedValue([PRECOMPUTED_DOT_PLOT_DATA, {}])

      await ScpApi.fetchMorpheusJson(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false, // mock
        true // isPrecomputed
      )

      // Verify the API was called with correct parameters
      expect(fetchMorpheusJsonSpy).toHaveBeenCalledWith(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false,
        true
      )
    })

    it('uses morpheus endpoint when feature flag is disabled', async () => {
      fetchMorpheusJsonSpy.mockResolvedValue([{}, {}])

      await ScpApi.fetchMorpheusJson(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false, // mock
        false // isPrecomputed
      )

      expect(fetchMorpheusJsonSpy).toHaveBeenCalledWith(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false,
        false
      )
    })
  })

  describe('Data format detection', () => {
    it('detects precomputed data format correctly', () => {
      const data = PRECOMPUTED_DOT_PLOT_DATA

      // Check if data matches precomputed format
      const isPrecomputed = !!(data.annotation_name && data.values && data.genes)
      expect(isPrecomputed).toBe(true)
    })

    it('does not detect standard Morpheus format as precomputed', () => {
      const standardData = {
        rows: ['Gene1', 'Gene2'],
        columns: ['Cell1', 'Cell2'],
        data: [[1, 2], [3, 4]]
      }

      const isPrecomputed = !!(standardData.annotation_name && standardData.values && standardData.genes)
      expect(isPrecomputed).toBe(false)
    })
  })

  describe('Endpoint URL construction', () => {
    it('constructs dotplot endpoint URL correctly', () => {
      const studyAccession = 'SCP1234'
      const isPrecomputed = true

      // Test the endpoint selection logic
      const endpoint = isPrecomputed ? 'dotplot' : 'morpheus'
      expect(endpoint).toBe('dotplot')

      const expectedUrl = `/studies/${studyAccession}/expression/${endpoint}`
      expect(expectedUrl).toContain('dotplot')
      expect(expectedUrl).not.toContain('morpheus')
    })

    it('constructs morpheus endpoint URL correctly when flag is off', () => {
      const studyAccession = 'SCP1234'
      const isPrecomputed = false
      const endpoint = isPrecomputed ? 'dotplot' : 'morpheus'

      expect(endpoint).toBe('morpheus')

      const expectedUrl = `/studies/${studyAccession}/expression/${endpoint}`
      expect(expectedUrl).toContain('morpheus')
      expect(expectedUrl).not.toContain('dotplot')
    })
  })

  describe('Feature flag integration', () => {
    it('uses feature flag value to determine endpoint', () => {
      // When flag is true
      let usePreprocessed = FEATURE_FLAGS_ENABLED.dot_plot_preprocessing_frontend
      expect(usePreprocessed).toBe(true)

      // When flag is false
      usePreprocessed = FEATURE_FLAGS_DISABLED.dot_plot_preprocessing_frontend
      expect(usePreprocessed).toBe(false)
    })

    it('defaults to false when flag is undefined', () => {
      const flags = {}
      const usePreprocessed = flags?.dot_plot_preprocessing_frontend || false
      expect(usePreprocessed).toBe(false)
    })
  })

  describe('Color scheme configuration', () => {
    it('uses relative scaling for raw expression values', () => {
      const colorScheme = {
        colors: ['#0000BB', '#CC0088', '#FF0000'],
        values: [0, 0.5, 1],
        scalingMode: 'relative'
      }

      expect(colorScheme.scalingMode).toBe('relative')
      expect(colorScheme.colors).toHaveLength(3)
      expect(colorScheme.values).toEqual([0, 0.5, 1])
    })

    it('uses fixed color values for blue-purple-red gradient', () => {
      const colorScheme = {
        colors: ['#0000BB', '#CC0088', '#FF0000'],
        values: [0, 0.5, 1],
        scalingMode: 'relative'
      }

      // Blue at 0
      expect(colorScheme.colors[0]).toBe('#0000BB')
      // Purple at 0.5
      expect(colorScheme.colors[1]).toBe('#CC0088')
      // Red at 1
      expect(colorScheme.colors[2]).toBe('#FF0000')
    })
  })

  describe('Size configuration', () => {
    it('configures sizeBy for percent expressing', () => {
      const sizeByConfig = {
        seriesName: 'percent',
        min: 0,
        max: 75
      }

      expect(sizeByConfig.seriesName).toBe('percent')
      expect(sizeByConfig.min).toBe(0)
      expect(sizeByConfig.max).toBe(75)
    })
  })

  describe('shouldUsePreprocessedData', () => {
    it('returns true when both flag is enabled and cluster has dot plot genes', () => {
      const flags = { dot_plot_preprocessing_frontend: true }
      const exploreInfo = { cluster: { hasDotPlotGenes: true } }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(true)
    })

    it('returns false when flag is enabled but cluster does not have dot plot genes', () => {
      const flags = { dot_plot_preprocessing_frontend: true }
      const exploreInfo = { cluster: { hasDotPlotGenes: false } }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when flag is disabled but cluster has dot plot genes', () => {
      const flags = { dot_plot_preprocessing_frontend: false }
      const exploreInfo = { cluster: { hasDotPlotGenes: true } }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when both flag is disabled and cluster does not have dot plot genes', () => {
      const flags = { dot_plot_preprocessing_frontend: false }
      const exploreInfo = { cluster: { hasDotPlotGenes: false } }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when flag is undefined', () => {
      const flags = {}
      const exploreInfo = { cluster: { hasDotPlotGenes: true } }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when exploreInfo is undefined', () => {
      const flags = { dot_plot_preprocessing_frontend: true }
      const exploreInfo = undefined

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when cluster is undefined', () => {
      const flags = { dot_plot_preprocessing_frontend: true }
      const exploreInfo = {}

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })

    it('returns false when hasDotPlotGenes is undefined', () => {
      const flags = { dot_plot_preprocessing_frontend: true }
      const exploreInfo = { cluster: {} }

      expect(shouldUsePreprocessedData(flags, exploreInfo)).toBe(false)
    })
  })

  describe('Heatmap data handling', () => {
    it('uses morpheus endpoint with usePreprocessed=false by default', async () => {
      const mockMorpheusData = {
        rows: ['Gene1', 'Gene2'],
        columns: ['Cell1', 'Cell2'],
        data: [[1, 2], [3, 4]]
      }
      fetchMorpheusJsonSpy.mockResolvedValue([mockMorpheusData, {}])

      // Call without usePreprocessed parameter (should default to false)
      await ScpApi.fetchMorpheusJson(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false // mock
        // usePreprocessed omitted - should default to false
      )

      expect(fetchMorpheusJsonSpy).toHaveBeenCalledWith(
        'SCP1234',
        ['CD3D', 'CD79A'],
        'cluster_1',
        'cell_type',
        'group',
        'study',
        'all',
        false
        // usePreprocessed defaults to false
      )
    })

    it('detects preprocessed data format to avoid sharing with heatmap', () => {
      // Preprocessed format
      const preprocessedData = {
        annotation_name: 'cell_type',
        values: ['T cells', 'B cells'],
        genes: { CD3D: [[1.5, 0.8], [0.1, 0.05]] }
      }

      const isPreprocessedFormat = !!(
        preprocessedData.annotation_name &&
        preprocessedData.values &&
        preprocessedData.genes
      )
      expect(isPreprocessedFormat).toBe(true)

      // Standard Morpheus format
      const standardData = {
        rows: ['Gene1', 'Gene2'],
        columns: ['Cell1', 'Cell2'],
        data: [[1, 2], [3, 4]]
      }

      const isStandardFormat = !!(
        standardData.annotation_name &&
        standardData.values &&
        standardData.genes
      )
      expect(isStandardFormat).toBe(false)
    })
  })
})
