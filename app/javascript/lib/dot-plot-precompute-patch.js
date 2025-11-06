/**
 * Monkeypatch for Morpheus to accept pre-computed dot plot data
 * Data format: [mean_expression, percent_expressing]
 * Mean expression values are normalized per-gene (per-row) to 0-1 range for proper color scaling
 */

(function() {
  'use strict'

  /**
   * Apply the dot plot patch to Morpheus once it's loaded
   * Waits for window.morpheus to be available before patching
   */
  function applyDotPlotPatch() {
    if (typeof window.morpheus === 'undefined') {
      // Morpheus not loaded yet, wait a bit and try again
      setTimeout(applyDotPlotPatch, 100)
      return
    }

    /**
     * Convert your dot plot JSON format to a Morpheus dataset
     */
    window.morpheus.DotPlotConverter = {

      createDataset(data) {
        const cellTypes = data.values
        const geneNames = Object.keys(data.genes)
        const nRows = geneNames.length
        const nCols = cellTypes.length

        // Create dataset with Float32 data type
        // The dataset name becomes the first series name by default
        const dataset = new window.morpheus.Dataset({
          name: 'Mean Expression',
          rows: nRows,
          columns: nCols,
          dataType: 'Float32'
        })

        // Add second series for the size metric (percent expressing)
        // Morpheus uses 'percent' for sizing in dot plots
        dataset.addSeries({
          name: 'percent',
          dataType: 'Float32'
        })

        // Set up row metadata (genes)
        const rowIds = dataset.getRowMetadata().add('id')
        geneNames.forEach((gene, i) => {
          rowIds.setValue(i, gene)
        })

        // Set up column metadata (cell types)
        const colIds = dataset.getColumnMetadata().add('id')
        const cellTypeMetadata = dataset.getColumnMetadata().add(data.annotation_name || 'Cell Type')
        cellTypes.forEach((cellType, j) => {
          colIds.setValue(j, cellType)
          cellTypeMetadata.setValue(j, cellType)
        })

        // Fill in the data
        // Series 0: mean expression (for color) - will be normalized per-gene (row)
        // Series 1: percent expressing (for size) - will be scaled to 0-100
        // Data format: values[0] = mean_expression, values[1] = percent_expressing
        geneNames.forEach((gene, i) => {
          const geneData = data.genes[gene]

          geneData.forEach((values, j) => {
            const meanExpression = values[0]
            const percentExpressing = values[1]

            // Use raw mean expression values, but convert zeros to NaN
            // This excludes them from Morpheus color scaling while preserving actual values
            const expressionValue = meanExpression === 0 ? NaN : meanExpression
            dataset.setValue(i, j, expressionValue, 0) // Raw mean expression for color (zeros as NaN)
            // Scale percent expressing to 0-100 range for better sizing
            dataset.setValue(i, j, percentExpressing * 100, 1) // Percent expressing (0-100) for size
          })
        })

        return dataset
      },

      /**
       * Add custom properties to enable dot plot mode
       */
      configureDotPlot(dataset) {
        // Add a property to indicate this is dot plot data
        dataset._isDotPlot = true
        dataset._dotPlotSizeSeries = 1 // Percent expressing
        dataset._dotPlotColorSeries = 0 // Mean expression

        return dataset
      }
    }

    /**
     * Register a custom JSON reader for dot plot format
     */
    const OriginalJsonReader = window.morpheus.JsonDatasetReader

    window.morpheus.JsonDatasetReader = function() {
      OriginalJsonReader.call(this)
    }

    window.morpheus.JsonDatasetReader.prototype = Object.create(OriginalJsonReader.prototype)

    const originalRead = OriginalJsonReader.prototype.read
    window.morpheus.JsonDatasetReader.prototype.read = function(fileOrUrl, callback) {
      const self = this

      // Check if it's our dot plot format
      window.morpheus.Util.getText(fileOrUrl).then(text => {
        try {
          const data = JSON.parse(text)

          // Check if it matches our dot plot format
          if (data.annotation_name && data.values && data.genes) {
            let dataset = window.morpheus.DotPlotConverter.createDataset(data)
            dataset = window.morpheus.DotPlotConverter.configureDotPlot(dataset)
            callback(null, dataset)
          } else {
            // Fall back to original reader
            originalRead.call(self, fileOrUrl, callback)
          }
        } catch (err) {
          callback(err)
        }
      }).catch(err => {
        callback(err)
      })
    }

    /**
     * Helper to create dot plot directly from your data object
     */
    window.createMorpheusDotPlot = function(data) {
      const dataset = window.morpheus.DotPlotConverter.createDataset(data)
      return window.morpheus.DotPlotConverter.configureDotPlot(dataset)
    }

    /**
     * Patch the HeatMap to properly handle dot plot sizing with __count series
     */
    const OriginalHeatMap = window.morpheus.HeatMap
    window.morpheus.HeatMap = function(options) {
      const heatmap = new OriginalHeatMap(options)

      // Check if this is a precomputed dot plot dataset
      if (options.dataset && options.dataset._isDotPlot) {
        // Force the heatmap to use series 1 for sizing
        if (heatmap.heatMapElementCanvas) {
          heatmap.heatMapElementCanvas.sizeBySeriesIndex = 1
        }
      }

      return heatmap
    }

    // Copy static properties
    Object.setPrototypeOf(window.morpheus.HeatMap, OriginalHeatMap)
    window.morpheus.HeatMap.prototype = OriginalHeatMap.prototype
  }

  // Start trying to apply the patch
  applyDotPlotPatch()
})()
