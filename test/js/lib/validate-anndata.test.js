import {
  getHdf5File, parseAnnDataFile, getAnnDataHeaders, checkOntologyIdFormat
} from 'lib/validation/validate-anndata'

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
    const remoteProps = {url}
    const hdf5File = await getHdf5File(url, remoteProps)
    const headers = await getAnnDataHeaders(hdf5File)
    expect(headers).toEqual(expectedHeaders)
  })

  it('Reports AnnData with valid headers as valid', async () => {
    // eslint-disable-next-line max-len
    const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test.h5ad'
    const parseResults = await parseAnnDataFile(url)
    expect(parseResults.issues).toHaveLength(0)
  })

  it('Reports AnnData with invalid headers as invalid', async () => {
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

  it('Reports valid ontology IDs as valid', async () => {
    const issues = await checkOntologyIdFormat(
      // Underscore or colon can delimit shortname and number;
      // disease can use MONDO or PATO IDs.
      'disease', ['MONDO_0000001', 'MONDO:0000001', 'PATO:0000001']
    )
    expect(issues).toHaveLength(0)
  })

  // TODO: Uncomment this after row-level AnnData parsing PR is merged
  // it('Parses AnnData rows and reports invalid ontology IDs', async () => {
  //   // eslint-disable-next-line max-len
  //   const url = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata_test_invalid_disease.h5ad'
  //   const parseResults = await parseAnnDataFile(url)

  //   expect(parseResults.issues).toHaveLength(1)

  //   const expectedIssue = [
  //     'error',
  //     'ontology:label-lookup-error',
  //     'Ontology ID "FOO_0000042" is not among accepted ontologies (MONDO, PATO) for key "disease"'
  //   ]
  //   expect(parseResults.issues[0]).toEqual(expectedIssue)
  // })
})
