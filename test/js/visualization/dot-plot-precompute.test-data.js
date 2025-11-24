/**
 * Test data for dot plot precompute patch tests
 */

// Mock pre-computed dot plot data from backend
export const PRECOMPUTED_DOT_PLOT_DATA = {
  annotation_name: 'cell_type',
  values: ['T cells', 'B cells', 'NK cells', 'Monocytes'],
  genes: {
    'CD3D': [
      [2.5, 0.95], // T cells: [mean_expression, percent_expressing]
      [0.1, 0.05], // B cells
      [0.3, 0.15], // NK cells
      [0.0, 0.0]   // Monocytes
    ],
    'CD79A': [
      [0.2, 0.1],  // T cells
      [3.1, 0.98], // B cells
      [0.1, 0.05], // NK cells
      [0.0, 0.0]   // Monocytes
    ],
    'NKG7': [
      [1.2, 0.65], // T cells
      [0.3, 0.15], // B cells
      [2.8, 0.92], // NK cells
      [0.5, 0.25]  // Monocytes
    ],
    'UBC': [
      [1.926, 0.9237], // T cells
      [2.081, 0.969],  // B cells
      [2.012, 0.7749], // NK cells
      [3.394, 0.95]    // Monocytes (highest)
    ]
  }
}

// Mock pre-computed data with all zeros for a gene
export const PRECOMPUTED_WITH_ZEROS = {
  annotation_name: 'tissue',
  values: ['Brain', 'Liver', 'Heart'],
  genes: {
    'GENE1': [
      [0, 0],
      [0, 0],
      [0, 0]
    ],
    'GENE2': [
      [1.5, 0.8],
      [2.3, 0.9],
      [0.8, 0.4]
    ]
  }
}

// Mock pre-computed data with single cell type
export const PRECOMPUTED_SINGLE_CELL_TYPE = {
  annotation_name: 'cell_type',
  values: ['Neurons'],
  genes: {
    'GENE1': [[2.5, 0.95]],
    'GENE2': [[1.8, 0.75]]
  }
}

// Expected Morpheus dataset structure after conversion
export const EXPECTED_MORPHEUS_STRUCTURE = {
  seriesCount: 2,
  series0Name: 'Mean Expression',
  series1Name: 'percent',
  rowCount: 4, // 4 genes in PRECOMPUTED_DOT_PLOT_DATA
  columnCount: 4 // 4 cell types
}

// Mock feature flags
export const FEATURE_FLAGS_ENABLED = {
  dot_plot_preprocessing_frontend: true
}

export const FEATURE_FLAGS_DISABLED = {
  dot_plot_preprocessing_frontend: false
}
