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
        console.log('in patch createDataset with data:', data)
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
          
          // Find min and max mean expression for this gene across all cell types
          // Exclude zeros (no expression) from min/max calculation for better color scaling
          let minExpr = Infinity
          let maxExpr = -Infinity
          geneData.forEach(values => {
            const meanExpression = values[0]
            // Only include non-zero values in min/max calculation
            if (meanExpression > 0) {
              if (meanExpression < minExpr) {
                minExpr = meanExpression
              }
              if (meanExpression > maxExpr) {
                maxExpr = meanExpression
              }
            }
          })
          
          // Handle edge cases
          if (minExpr === Infinity) {
            // All values are zero
            minExpr = 0
            maxExpr = 0
          }
          const range = maxExpr - minExpr
          const normalizedRange = range === 0 ? 0 : 1 / range
          
          // Debug: Log normalization for first gene and UBC
          if (i === 0 || gene === 'UBC') {
            console.log(`Gene ${gene}: min=${minExpr}, max=${maxExpr}, range=${range} (zeros excluded from min/max)`)
          }
          
          geneData.forEach((values, j) => {
            const meanExpression = values[0]
            const percentExpressing = values[1]
            
            // Normalize mean expression to 0-1 range per-gene
            // Zero values map to 0 (blue), non-zero values scale between min and max
            let normalizedMeanExpression
            if (meanExpression === 0) {
              normalizedMeanExpression = 0
            } else if (range === 0) {
              normalizedMeanExpression = 0.5
            } else {
              normalizedMeanExpression = (meanExpression - minExpr) * normalizedRange
            }
            
            // Debug: Log normalized values for first gene and UBC
            if ((i === 0 || gene === 'UBC') && j < 3) {
              console.log(`  ${gene}[${j}]: raw=${meanExpression}, normalized=${normalizedMeanExpression}, %expr=${percentExpressing}`)
            }
            
            dataset.setValue(i, j, normalizedMeanExpression, 0) // Normalized mean expression (0-1) for color
            // Scale percent expressing to 0-100 range for better sizing
            dataset.setValue(i, j, percentExpressing * 100, 1) // Percent expressing (0-100) for size
          })
        }) // Debug: log a sample to verify data
        if (geneNames.length > 0) {
          console.log('Sample dot plot data for gene', geneNames[0], ':')
          console.log('  Mean expression (series 0):', dataset.getValue(0, 0, 0))
          console.log('  Percent expressing (series 1):', dataset.getValue(0, 0, 1))
          console.log('  Dataset has', dataset.getSeriesCount(), 'series')
          console.log('  Series 0 name:', dataset.getName(0))
          console.log('  Series 1 name:', dataset.getName(1))
        }

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
        console.log('Patching HeatMap for precomputed dot plot')

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
