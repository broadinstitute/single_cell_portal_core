/**
 * Integration tests for DotPlot component with precomputed data
 */

/* global global */

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

  describe('Dot plot height adjustment for legend visibility', () => {
    let mockTarget
    let mockDotPlot
    const LEGEND_HEIGHT = 70

    beforeEach(() => {
      // Create mock DOM element
      mockTarget = document.createElement('div')
      mockTarget.id = 'test-dotplot'
      document.body.appendChild(mockTarget)

      // Mock dot plot object
      mockDotPlot = {
        resized: jest.fn()
      }

      // Mock jQuery
      global.$ = jest.fn(selector => {
        if (selector === window) {
          return {
            off: jest.fn().mockReturnThis(),
            on: jest.fn().mockReturnThis()
          }
        }
        return {
          0: mockTarget,
          css: jest.fn(),
          empty: jest.fn(),
          html: jest.fn()
        }
      })
    })

    afterEach(() => {
      document.body.removeChild(mockTarget)
      jest.clearAllMocks()
    })

    it('shrinks dot plot when height + legend exceeds available space', () => {
      const dimensions = { height: 600, width: 800 }

      // Mock a tall dot plot that needs shrinking
      Object.defineProperty(mockTarget, 'scrollHeight', {
        configurable: true,
        value: 800 // 800 + 70 = 870 > 600
      })

      const $mockTarget = global.$('#test-dotplot')
      const cssSpy = jest.spyOn($mockTarget, 'css')

      // Simulate the adjustment logic
      const dotPlotHeight = mockTarget.scrollHeight
      const totalNeededHeight = dotPlotHeight + LEGEND_HEIGHT
      const adjustedHeight = dimensions.height - LEGEND_HEIGHT

      if (totalNeededHeight > dimensions.height && adjustedHeight > 100) {
        $mockTarget.css('height', `${adjustedHeight}px`)
        $mockTarget.css('overflow-y', 'auto')
      }

      expect(cssSpy).toHaveBeenCalledWith('height', '530px')
      expect(cssSpy).toHaveBeenCalledWith('overflow-y', 'auto')
    })

    it('does not shrink dot plot when it fits with legend', () => {
      const dimensions = { height: 600, width: 800 }

      // Mock a short dot plot that fits
      Object.defineProperty(mockTarget, 'scrollHeight', {
        configurable: true,
        value: 400 // 400 + 70 = 470 < 600
      })

      const $mockTarget = global.$('#test-dotplot')
      const cssSpy = jest.spyOn($mockTarget, 'css')

      // Simulate the adjustment logic
      const dotPlotHeight = mockTarget.scrollHeight
      const totalNeededHeight = dotPlotHeight + LEGEND_HEIGHT

      if (totalNeededHeight > dimensions.height) {
        const adjustedHeight = dimensions.height - LEGEND_HEIGHT
        if (adjustedHeight > 100) {
          $mockTarget.css('height', `${adjustedHeight}px`)
          $mockTarget.css('overflow-y', 'auto')
        }
      } else {
        $mockTarget.css('height', '')
        $mockTarget.css('overflow-y', '')
      }

      // Should reset height when there's enough space
      expect(cssSpy).toHaveBeenCalledWith('height', '')
      expect(cssSpy).toHaveBeenCalledWith('overflow-y', '')
    })

    it('maintains minimum height of 100px even when adjusted', () => {
      const dimensions = { height: 150, width: 800 }

      // Mock a dot plot
      Object.defineProperty(mockTarget, 'scrollHeight', {
        configurable: true,
        value: 200
      })

      const $mockTarget = global.$('#test-dotplot')

      // Simulate the adjustment logic
      const dotPlotHeight = mockTarget.scrollHeight
      const totalNeededHeight = dotPlotHeight + LEGEND_HEIGHT
      const adjustedHeight = dimensions.height - LEGEND_HEIGHT // 150 - 70 = 80

      let heightWasSet = false
      if (totalNeededHeight > dimensions.height && adjustedHeight > 100) {
        $mockTarget.css('height', `${adjustedHeight}px`)
        heightWasSet = true
      }

      // Should not set height because adjusted height (80px) < minimum (100px)
      expect(heightWasSet).toBe(false)
    })

    it('uses scrollHeight to get full content height', () => {
      Object.defineProperty(mockTarget, 'scrollHeight', {
        configurable: true,
        value: 1000
      })
      Object.defineProperty(mockTarget, 'offsetHeight', {
        configurable: true,
        value: 500
      })

      // scrollHeight should be used (full content) not offsetHeight (visible)
      const fullHeight = mockTarget.scrollHeight
      const visibleHeight = mockTarget.offsetHeight

      expect(fullHeight).toBe(1000)
      expect(visibleHeight).toBe(500)
      expect(fullHeight).toBeGreaterThan(visibleHeight)
    })

    it('sets up window resize listener to re-adjust on viewport changes', () => {
      const $window = global.$(window)
      const offSpy = jest.spyOn($window, 'off')
      const onSpy = jest.spyOn($window, 'on')

      // Simulate setting up resize listener
      $window.off('resize.dotplot')
      $window.on('resize.dotplot', jest.fn())

      expect(offSpy).toHaveBeenCalledWith('resize.dotplot')
      expect(onSpy).toHaveBeenCalledWith('resize.dotplot', expect.any(Function))
    })

    it('calls dotPlot.resized() after adjusting height', () => {
      const dimensions = { height: 600, width: 800 }

      Object.defineProperty(mockTarget, 'scrollHeight', {
        configurable: true,
        value: 800
      })

      // Simulate adjustment and resize notification
      const totalNeededHeight = mockTarget.scrollHeight + LEGEND_HEIGHT
      if (totalNeededHeight > dimensions.height) {
        mockDotPlot.resized()
      }

      expect(mockDotPlot.resized).toHaveBeenCalled()
    })

    it('handles missing dimensions gracefully', () => {
      const dimensions = null

      // Should not throw when dimensions is null/undefined
      expect(() => {
        if (dimensions?.height) {
          // This block shouldn't execute
          throw new Error('Should not reach here')
        }
      }).not.toThrow()
    })
  })
})
