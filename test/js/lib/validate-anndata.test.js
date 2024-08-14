import {parseAnnDataFile} from 'lib/validation/validate-anndata'

describe('Client-side file validation for AnnData', () => {
  it('Validates AnnData file headers', async () => {
    const url = 'https://github.com/broadinstitute/scp-ingest-pipeline/raw/development/tests/data/anndata/anndata_test.h5ad'
    const parseResults = parseAnnDataFile(url)
  })
})
