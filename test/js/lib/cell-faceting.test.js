import { allAnnots, facetData } from './cell-faceting.test-data'
import * as ScpApi from 'lib/scp-api'

import { initCellFaceting } from 'lib/cell-faceting'

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

    const selectedCluster = 'All Cells UMAP'
    const selectedAnnot = { name: 'donor_id', type: 'group', scope: 'study' }
    const studyAccession = 'SCP152'

    const cellFaceting = await initCellFaceting(
      selectedCluster, selectedAnnot, studyAccession, allAnnots
    )

    const filtersByFacet = cellFaceting.filtersByFacet
    const filterableCells = cellFaceting.filterableCells

    // console.log('facets', facets)
    console.log('filtersByFacet', filtersByFacet)
    // console.log('filterableCells', filterableCells)

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
  })
})
