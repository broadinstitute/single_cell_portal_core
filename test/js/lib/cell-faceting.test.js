import { allAnnots, facetData } from './cell-faceting.test-data'
import * as ScpApi from 'lib/scp-api'

import { initCellFaceting, filterCells } from 'lib/cell-faceting'

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
    const filtersByFacet = cellFaceting.filtersByFacet
    const filterableCells = cellFaceting.filterableCells

    const expectedFilterableCells99 = {
      'allCellsIndex': 99,
      'facetIndex': [1, 1, 0, 0, 0]
    }

    const expectedInfantSickYN = ['no']

    expect(filterableCells[99]).toMatchObject(expectedFilterableCells99)
    expect(filtersByFacet['infant_sick_YN--group--study']).toEqual(expectedInfantSickYN)

    // Test actual cell faceting
    const selections = {
      'cell_type__ontology_label--group--study': ['epithelial cell'],
      'General_Celltype--group--study': ['LC1', 'LC2']
    }
    const newFilteredCells = filterCells(
      selections, cellsByFacet, facets, filtersByFacet, filterableCells, facets
    )[0]
    expect(newFilteredCells).toHaveLength(33)
  })
})
