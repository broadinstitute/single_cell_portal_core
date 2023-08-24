import { allAnnots, facetData } from './cell-faceting.test-data'
import * as ScpApi from 'lib/scp-api'

import { initCellFaceting, filterCells } from 'lib/cell-faceting'

// Test functionality to filter cells shown in plots across annotation facets
describe('Cell faceting', () => {
  it('filters cells by group filters in annotation facets', async () => {
    // To manually test:
    // 1. Go to DE pilot study ("Human milk" / "Cellular and transcriptional diversity over the course of human lactation")
    // 2. (TODO) In "Annotation" menu, select "Category"

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
      'cell_type__ontology_label--group--study': 1,
      'General_Celltype--group--study': 1,
      'infant_sick_YN--group--study': 0,
      'ethnicity__ontology_label--group--study': 0,
      'biosample_id--group--study': 0
    }

    const expectedInfantSickYN = ['no', 'NA', 'yes']

    expect(filterableCells[99]).toMatchObject(expectedFilterableCells99)
    expect(filtersByFacet['infant_sick_YN--group--study']).toEqual(expectedInfantSickYN)

    // Test actual cell faceting
    const selections = {
      'cell_type__ontology_label--group--study': ['epithelial cell'],
      'General_Celltype--group--study': ['LC1', 'LC2']
    }
    const newFilteredCells = filterCells(
      selections, cellsByFacet, facets, filtersByFacet, filterableCells
    )[0]
    expect(newFilteredCells).toHaveLength(40)
  })
})
