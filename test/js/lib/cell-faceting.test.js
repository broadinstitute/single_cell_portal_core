import { allAnnots, facetData } from './cell-faceting.test-data'
import * as ScpApi from 'lib/scp-api'

import {
  initCellFaceting, filterCells, applyNumericFilters
} from 'lib/cell-faceting'

// Test functionality to filter cells shown in plots across annotation facets
describe('Cell faceting', () => {
  it('filters cells by group filters in annotation facets', async () => {
    // To manually test:
    // 1. In ExploreDisplayTabs.jsx, uncomment the line `// window.SCP.updateFilteredCells = updateFilteredCells`
    // 2. Go to DE pilot study ("Human milk - differential expression")
    // 3. In the Console panel in DevTools, run `window.SCP.updateFilteredCells({'cell_type__ontology_label--group--study': ['epithelial cell']}) // Apply 1 facet, 1 filter`
    // 4.  Confirm the cluster scatter plot updates to show only cells in the "LC1" and "LC2" groups, with cell counts 4427 and 35398 respectively.
    // 5. In Console, run `window.SCP.updateFilteredCells({'cell_type__ontology_label--group--study': ['epithelial cell'], 'infant_sick_YN--group--study': ['yes', 'NA']}) // Apply 2 facets, 3 filters`
    // 6. Confirm LC1 cell count updates to 1090, LC2 to 10725.
    // 7. In Console, run `window.SCP.updateFilteredCells({}) // Clear filters`
    // 8. Confirm cluster scatter plots returns to its original state
    // 9. In ExploreDisplayTabs.jsx, comment out the line `window.SCP.updateFilteredCells = updateFilteredCells`

    const fetchAnnotationFacets = jest.spyOn(ScpApi, 'fetchAnnotationFacets')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchAnnotationFacets.mockImplementation(() => Promise.resolve(
      facetData
    ))

    // Test client-side cell faceting setup functionality
    const selectedCluster = 'All Cells UMAP'
    const selectedAnnot = { name: 'donor_id', type: 'group', scope: 'study' }
    const studyAccession = 'SCP152'

    const cellFaceting = await initCellFaceting(
      selectedCluster, selectedAnnot, studyAccession, allAnnots
    )

    const cellsByFacet = cellFaceting.cellsByFacet
    const facets = cellFaceting.facets
    const filterableCells = cellFaceting.filterableCells

    const expectedFilterableCells99 = {
      'allCellsIndex': 99,
      'facetIndex': [1, 1, 0, 0, 0]
    }

    expect(filterableCells[99]).toMatchObject(expectedFilterableCells99)

    // Test actual cell faceting
    const selections = {
      'cell_type__ontology_label--group--study': ['epithelial cell'],
      'General_Celltype--group--study': ['LC1', 'LC2']
    }
    const newFilteredCells = filterCells(
      selections, cellsByFacet, facets, filterableCells, facets
    )[0]
    expect(newFilteredCells).toHaveLength(33)
  })

  it('filters cells by numeric filters', async () => {
    expect(applyNumericFilters(2, [[['=', 2]], true])).toStrictEqual(true)
    expect(applyNumericFilters(2, [[['=', 1.3]], true])).toStrictEqual(false)
    expect(applyNumericFilters(20, [[['>=', 6]], true])).toStrictEqual(true)
    expect(applyNumericFilters(20, [[['<', 6]], true])).toStrictEqual(false)
    expect(applyNumericFilters(20, [[['>', 20]], true])).toStrictEqual(false)
    expect(applyNumericFilters(20, [[['between', [5, 42]]], true])).toStrictEqual(true)
    expect(applyNumericFilters(2, [[['between', [0, 2]]], true])).toStrictEqual(true) // test inclusiveness
    expect(applyNumericFilters(2, [[['between', [0, 2.1]]], true], 2)).toStrictEqual(true) // test inclusiveness
    expect(applyNumericFilters(10, [[['between', [0, 2]], ['between', [8, 20]]], true])).toStrictEqual(true)
    expect(applyNumericFilters(5, [[['between', [0, 2]], ['between', [8, 20]]], true])).toStrictEqual(false)
  })

  it('filters cells even when a raw data has numeric annotation with 1 value for all cells', async () => {
    // This tests a fix for a bug in cell filtering that was first observed in production SCP2126.
    // The bug causes cell filtering to fail when any filter is changed.  It is caused by
    // a numeric facet ("Weeks post dose") that has the same number (4) for all cells.  Cell filtering
    // requires a set of cells to have > 1 value.  This tests special handling when that constraint is
    // violated in numeric annotations.
    //
    // Once ticket SCP-5572 is resolved, this test will be obsolete and should be deleted.

    const allAnnotsScp5554 = [
      {
        'name': 'sex',
        'type': 'group',
        'values': [
          'female',
          'male'
        ],
        'scope': 'study',
        'is_differential_expression_enabled': false
      },
      {
        'name': 'cell_type__ontology_label',
        'type': 'group',
        'values': [
          'neuron',
          'fibroblast'
        ],
        'scope': 'study',
        'is_differential_expression_enabled': false
      },
      {
        'name': 'weeks_post_dose',
        'type': 'numeric',
        'values': [],
        'scope': 'study',
        'is_differential_expression_enabled': false
      }
    ]

    const constantNumericValue = 4
    const facetDataScp5554 = {
      'cells': [
        [1, 1, constantNumericValue],
        [0, 1, constantNumericValue],
        [1, 0, constantNumericValue],
        [0, 0, constantNumericValue]
      ],
      'facets': [
        {
          'annotation': 'cell_type__ontology_label--group--study',
          'groups': [
            'neuron',
            'fibroblast'
          ]
        },
        {
          'annotation': 'sex--group--study',
          'groups': [
            'female',
            'male'
          ]
        },
        {
          'annotation': 'weeks_post_dose--numeric--study',
          'groups': []
        }
      ]
    }


    const fetchAnnotationFacets = jest.spyOn(ScpApi, 'fetchAnnotationFacets')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchAnnotationFacets.mockImplementation(() => Promise.resolve(
      facetDataScp5554
    ))

    // Test client-side cell faceting setup functionality
    const selectedCluster = 'scp_clustering_mouse_thalamus.tsv'
    const selectedAnnot = { name: 'Category', type: 'group', scope: 'study' }
    const studyAccession = 'SCP174'

    const cellFaceting = await initCellFaceting(
      selectedCluster, selectedAnnot, studyAccession, allAnnotsScp5554
    )

    const cellsByFacet = cellFaceting.cellsByFacet
    const facets = cellFaceting.facets
    const filterableCells = cellFaceting.filterableCells

    const expectedFilterableCells3 = {
      'allCellsIndex': 3,
      'facetIndex': [0, 0, 4]
    }

    expect(filterableCells[3]).toMatchObject(expectedFilterableCells3)

    // Test actual cell faceting
    const selections = {
      'cell_type__ontology_label--group--study': ['neuron'],

      // The `undefined` value below is how problematic facets -- i.e. numeric
      // annotations with 1 value for all cells -- get passed in to `filterCells`.
      // https://github.com/broadinstitute/single_cell_portal_core/pull/1996
      'weeks_post_dose--numeric--study': undefined
    }
    const filterCellsResult = filterCells(
      selections, cellsByFacet, facets, filterableCells, facets
    )
    console.log('filterCellsResult', filterCellsResult)
    // All cells in this example are neurons,
    expect(filterCellsResult[0]).toHaveLength(2)
  })
})
