import {parseAnnDataFile} from 'lib/validation/validate-anndata'

describe('Client-side file validation for AnnData', () => {
  it('Reports SCP-valid AnnData file as valid', async () => {
    // eslint-disable-next-line max-len
    const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test.h5ad'
    const parseResults = await parseAnnDataFile(url)
    expect(parseResults.issues).toHaveLength(0)
  })

  // TODO:
  // it('Reports SCP-invalid AnnData file as invalid', async () => {
  //   // eslint-disable-next-line max-len
  //   const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata/anndata_test_bad_header_no_species.h5ad'
  //   const parseResults = await parseAnnDataFile(url)
  // expect(parseResults.issues.length).toBeGreaterThan(0)
  // })
})
