import {parseAnnDataFile, getAnnDataHeaders} from 'lib/validation/validate-anndata'

describe('Client-side file validation for AnnData', () => {
  it('Parses AnnData headers', async () => {
    // eslint-disable-next-line max-len
    const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test.h5ad'
    const expectedHeaders = [
      '_index',
      'biosample_id',
      'disease',
      'disease__ontology_label',
      'donor_id',
      'library_preparation_protocol',
      'library_preparation_protocol__ontology_label',
      'organ',
      'organ__ontology_label',
      'sex',
      'species',
      'species__ontology_label'
    ]
    const headers = await getAnnDataHeaders(url)
    expect(headers).toEqual(expectedHeaders)
  })

  it('Reports SCP-valid AnnData file as valid', async () => {
    // eslint-disable-next-line max-len
    const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test.h5ad'
    const parseResults = await parseAnnDataFile(url)
    expect(parseResults.issues).toHaveLength(0)
  })

  // TODO (SCP-5718): Uncomment this negative test when test file is available in GitHub
  // it('Reports SCP-invalid AnnData file as invalid', async () => {
  //   // eslint-disable-next-line max-len
  //   const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata/anndata_test_bad_header_no_species.h5ad'
  //   const parseResults = await parseAnnDataFile(url)
  // expect(parseResults.issues.length).toBeGreaterThan(0)
  // })
})
