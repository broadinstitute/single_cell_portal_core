import {
  getHdf5File, parseAnnDataFile, getAnnDataHeaders, checkOntologyIdFormat
} from 'lib/validation/validate-anndata'

const BASE_URL = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data'

// TODO: Uncomment this after PR merge
// const BASE_URL = 'https://github.com/broadinstitute/single_cell_portal_core/raw/development/test/test_data/anndata'

describe('Client-side file validation for AnnData', () => {
  it('Parses AnnData headers', async () => {
    const url = `${BASE_URL}/anndata_test.h5ad`
    // const url = `${BASE_URL}/valid.h5ad` // Uncomment after PR merge
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
    const remoteProps = { url }
    const hdf5File = await getHdf5File(url, remoteProps)
    const headers = await getAnnDataHeaders(hdf5File)
    expect(headers).toEqual(expectedHeaders)
  })

  it('Reports AnnData with valid headers as valid', async () => {
    const url = `${BASE_URL}/anndata_test.h5ad`
    // const url = `${BASE_URL}/valid.h5ad` // Uncomment after PR merge
    const parseResults = await parseAnnDataFile(url)
    expect(parseResults.issues).toHaveLength(0)
  })

  it('Reports AnnData with invalid headers as invalid', async () => {
    const url = `${BASE_URL}/anndata_test_bad_header_no_species.h5ad`
    // const url = `${BASE_URL}/invalid_header_no_species.h5ad` // Uncomment after PR merge
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

  it('Parses AnnData rows and reports invalid ontology IDs', async () => {
    const url = `${BASE_URL}/anndata_test_invalid_disease.h5ad`
    // const url = `${BASE_URL}/invalid_disease_id.h5ad` // Uncomment after PR merge
    const parseResults = await parseAnnDataFile(url)

    expect(parseResults.issues).toHaveLength(1)

    const expectedIssue = [
      'error',
      'ontology:label-lookup-error',
      'Ontology ID "FOO_0000042" is not among accepted ontologies (MONDO, PATO) for key "disease"'
    ]
    expect(parseResults.issues[0]).toEqual(expectedIssue)
  })

  // // TODO: Uncomment after PR merge
  // it('Parses AnnData rows and reports invalid ontology labels', async () => {
  //   const url = `${BASE_URL}/invalid_disease_label.h5ad`
  //   const parseResults = await parseAnnDataFile(url)

  //   expect(parseResults.issues).toHaveLength(1)

  //   const expectedIssue = [
  //     'error',
  //     'ontology:label-lookup-error',
  //     'Invalid disease label "foo".  Valid labels for MONDO_0018076: tuberculosis, tuberculosis disease, active tuberculosis, Kochs disease, TB',
  //     {
  //       'subtype': 'ontology:invalid-label'
  //     }
  //   ]
  //   expect(parseResults.issues[0]).toEqual(expectedIssue)
  // })
})
