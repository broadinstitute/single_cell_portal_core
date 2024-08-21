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

  it('Reports SCP-invalid AnnData file as invalid', async () => {
    // eslint-disable-next-line max-len
    const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test_bad_header_no_species.h5ad'
    const parseResults = await parseAnnDataFile(url)

    expect(parseResults.issues).toHaveLength(1)

    const expectedIssue = [
      'error',
      'format:cap:metadata-missing-column',
      'File is missing required obs keys: species'
    ]
    expect(parseResults.issues[0]).toEqual(expectedIssue)
  })
})
