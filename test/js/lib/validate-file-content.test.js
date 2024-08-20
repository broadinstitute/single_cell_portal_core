import React from 'react'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import ValidateFile from 'lib/validation/validate-file'
import { REQUIRED_CONVENTION_COLUMNS } from 'lib/validation/shared-validation'
import { getLogProps } from 'lib/validation/log-validation'
import ValidationMessage from 'components/validation/ValidationMessage'
import * as MetricsApi from 'lib/metrics-api'
import * as UserProvider from '~/providers/UserProvider'

import { createMockFile } from './file-mock-utils'

const validateLocalFile = ValidateFile.validateLocalFile

describe('Client-side file validation', () => {
  jest
    .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
    .mockReturnValue({
      clientside_validation: true
    })

  it('catches and logs errors in files', async () => {
    const file = createMockFile({ fileName: 'metadata_bad_type_header.txt' })

    const fileType = 'Metadata'
    const fakeLog = jest.spyOn(MetricsApi, 'log')
    fakeLog.mockImplementation(() => { })

    const [{ errors }] = await validateLocalFile(file, { file_type: fileType })

    // Test library
    expect(errors).toHaveLength(1)

    // Test analytics
    expect(fakeLog).toHaveBeenCalledWith(
      'file-validation',
      expect.objectContaining({
        delimiter: 'tab',
        numColumns: 4,
        linesRead: 17,
        numTableCells: 68,
        fileType,
        fileName: 'metadata_bad_type_header.txt',
        fileSize: 566,
        fileMimeType: 'text/plain',
        isGzipped: false,
        status: 'failure',
        numErrors: 1,
        errors: [
          'Second row, first column must be "TYPE" (case insensitive). Your value was "notTYPE".'
        ],
        errorTypes: [
          'format:cap:type'
        ],
        perfTime: expect.any(Number), numWarnings: 0,
        warnings: [],
        warningTypes: []
      })
    )
  })


  it('prevents oversized log to Bard / Mixpanel', async () => {
    // Confirms low-level protection against HTTP 413 errors, which can cause
    // logging to Mixpanel to silently fail.

    const expectedNumErrors = 30000
    const expectedNumWarnings = 500
    const bigError = 'e'.repeat(2000)
    const bigWarning = 'w'.repeat(40000)

    const manyErrors = Array(expectedNumErrors).fill(
      ['error', 'foo:bar', bigError]
    )
    const manyWarnings = Array(expectedNumWarnings).fill(
      ['warning', 'baz:moo', bigWarning]
    )

    const errorObj = {
      errors: manyErrors,
      warnings: manyWarnings
    }

    const fileInfo = {
      delimiter: 'tab',
      numColumns: 99999999,
      linesRead: 99999999,
      numTableCells: 9999999999999,
      fileType: 'Metadata',
      fileName: 'actually_a_huge_expression_file.txt',
      fileSize: 99999999999999999,
      fileMimeType: 'text/plain',
      isGzipped: false,
      status: 'failure'
    }

    const perfTime = 900
    const logProps = getLogProps(fileInfo, errorObj, perfTime)

    expect(logProps.numErrors).toEqual(expectedNumErrors)
    expect(logProps.numWarnings).toEqual(expectedNumWarnings)
    expect(logProps.errors).toHaveLength(20)
    expect(logProps.warnings).toHaveLength(20)
    expect(logProps.errors[0]).toHaveLength(200)
    expect(logProps.warnings[0]).toHaveLength(200)
  })

  it('catches duplicate headers', async () => {
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_annotations.py#L56
    const file = createMockFile({ fileName: 'dup_headers_v2.0.0.tsv' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata' })
    expect(errors).toHaveLength(1)
  })

  it('catches missing header lines', async () => {
    const file = createMockFile({ content: 'NAME,X,Y', fileName: 'missing_headers.tsv' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:cap:missing-header-lines')
  })

  it('catches duplicate cell names in cluster file', async () => {
    const file = createMockFile({
      fileName: 'foo.txt',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCELL_0001,34.472,32.211\nCELL_0001,15.975,10.043'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:duplicate:cells-within-file')
    expect(errors[0][2]).toEqual('Cell names must be unique within a file. 1 duplicate found, including: CELL_0001')
  })

  it('catches duplicate cell names in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo1.csv',
      content: 'GENE,X,Y\nItm2a,0,5\nEif2b2,3,0\nEif2b2,1,9'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:duplicate:cells-within-file')
  })

  it('catches missing headers in metadata file', async () => {
    const file = createMockFile({
      fileName: 'foo2.txt',
      content: 'NAME,biosample_id,CellID\nTYPE,numeric,numeric\nCELL_0001,id1,cell1'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata', use_metadata_convention: true })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:cap:metadata-missing-column')
    expect(errors[0][2]).toContain(REQUIRED_CONVENTION_COLUMNS.slice(2).join(', '))
  })

  it('catches missing GENE header in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo4.txt',
      content: 'IS_NOT_GENE,X,Y\nItm2a,0,5\nEif2b2,3,0\nPf2b2,1,9'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:cap:missing-gene-column')
  })

  it('allows R-formatted header in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo4.txt',
      content: '\tX\tY\nItm2a\t0\t5\nEif2b2\t3\t0\nPf2b2\t1\t9'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(0)
  })

  it('catches wrong length R-formatted header in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo4.txt',
      content: ',X\nItm2a,0,5\nEif2b2,3,0\nPf2b2,1,9'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:cap:missing-gene-column')
  })

  it('catches non-numeric entry in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo5.csv',
      content: 'GENE,X,Y\nItm2a,p,5\nEif2b2,3,0\nPf2b2,1,9' // has an invalid value "p"
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:type:not-numeric')
  })

  it('catches empty entry in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo5b.tsv',
      content: (
        'GENE\tBM19_4dpp_r1_TAAGCAGTGGTA\tBM19_4dpp_r1_AAGCAGTGGTAT\n' +
        'A1BG\t0.0\t0.0\n' +
        'A1BG-AS1\t0.0\t0.0\n' +
        'A1CF\t\t\n' // There's an empty value on this line.
      )
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:type:not-numeric')
  })

  it('catches row with wrong number of columns in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo6.csv',
      content: 'GENE,X,Y\nItm2a,8,9\nEif2b2,3,0\nPf2b2,1'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:mismatch-column-number')
  })

  it('catches row with wrong number of columns in sparse matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo6.mtx',
      content: '%%MatrixMarket matrix coordinate integer general\n%\n4 8 9\n4 3 0\n4 1'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'MM Coordinate Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:mismatch-column-number')
  })

  it('catches missing header string in sparse matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo9.mtx',
      content: '%%MMahrket matrix coordinate integer general\n%\n4 8 9\n4 3 0\n4 1 2'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'MM Coordinate Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:cap:missing-mtx-value')
  })

  it('catches empty row in sparse matrix file', async () => {
    const file = createMockFile({
      fileName: 'fo06.mtx',
      content: '%%MatrixMarket matrix coordinate integer general\n%\n\n\n4 1 0'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'MM Coordinate Matrix' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('format:empty-row')
  })

  it('reports no error with sparse matrix file that has rows with trailing whitespace', async () => {
    const file = createMockFile({
      fileName: 'fo06.mtx',
      content: '%%MatrixMarket matrix coordinate integer general\n%\n4 8 9  \n4 8 9   \n4 1 0'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'MM Coordinate Matrix' })
    expect(errors).toHaveLength(0)
  })

  it('catches duplicate row values in barcodes file', async () => {
    const file = createMockFile({
      fileName: 'foo6.tsv',
      content: 'fake000\nfake001\nfake002\nfake000'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: '10X Barcodes File' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:duplicate:values-within-file')
  })

  it('catches duplicate row values in features file', async () => {
    const file = createMockFile({
      fileName: 'foo6.tsv',
      content: 'fake000\tboo\nfake001\tboo\nfake002\tbarr\nfake000\tboo'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: '10X Genes File' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('content:duplicate:values-within-file')
  })

  it('allows missing headers in metadata file if convention not used ', async () => {
    const file = createMockFile({
      fileName: 'foo.txt',
      content: 'NAME,biosample_id,CellID\nTYPE,numeric,numeric\nCELL_0001,34.472,32.211'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata', use_metadata_convention: false })
    expect(errors).toHaveLength(0)
  })

  it('catches mismatched label/value pairs in metadata files', async () => {
    const file = createMockFile({
      fileName: 'foo.txt',
      content: 'NAME,species,species__ontology_label\nTYPE,group,group\nc1,NCBITaxon_9606,Homo sapiens\nc2,NCBITaxon_9607,Homo sapiens'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata', use_metadata_convention: false })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('ontology:multiply-assigned-label')
    expect(errors[0][2]).toContain('Homo sapiens')
    expect(errors[0][2]).toContain('species')
  })

  it('catches group columns with >200 unique labels', async () => {
    const file = createMockFile({ fileName: 'metadata_drag_error.tsv' })
    const [{ warnings }] = await validateLocalFile(file, { file_type: 'Metadata', use_metadata_convention: true })
    expect(warnings).toHaveLength(2)
    expect(warnings[0][1]).toEqual('content:group-col-over-200')
    expect(warnings[0][2]).toContain('cell_type has over 200 unique values and so will not be visible in plots -- is this intended?')
  })

  it('reports no error with good cluster CSV file', async () => {
    // Confirms no false positive due to comma-separated values
    const file = createMockFile({ fileName: 'cluster_comma_delimited.csv' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(0)
  })

  it('catches gzipped file with txt extension', async () => {
    const file = createMockFile({ fileName: 'foo.txt', content: '\x1F\x2E3lkjf3' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('encoding:missing-gz-extension')
  })

  it('catches text file with .gz suffix', async () => {
    const file = createMockFile({ fileName: 'foo.gz', content: 'CELL\tX\tY' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(1)
    expect(errors[0][1]).toEqual('encoding:invalid-gzip-magic-number')
  })

  it('fails invalid gzipped file', async () => {
    // Confirms this validation does not report false negatives
    const file = createMockFile({ fileName: 'expression_matrix_example_bad.txt.gz' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors[0][1]).toEqual('format:cap:missing-gene-column')
    expect(errors).toHaveLength(2)
  })

  it('passes valid gzipped file', async () => {
    // Confirms this validation does not report false positives
    const file = createMockFile({ fileName: 'expression_matrix_example.txt.gz' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(0)
  })

  it('catches mismatched header counts', async () => {
    const file = createMockFile({ fileName: 'header_count_mismatch.tsv', contentType: 'text/tab-separated-values' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata' })
    expect(errors).toHaveLength(1)
  })

  it('catches multiple header errors', async () => {
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_annotations.py#L112
    const file = createMockFile({ fileName: 'error_headers_v2.0.0.tsv' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata' })
    expect(errors).toHaveLength(3)
  })

  it('fails when no coordinates in cluster file', async () => {
    // Confirms this validation does not report false negatives
    //
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_cluster.py#L9
    const file = createMockFile({ fileName: 'cluster_bad_no_coordinates.txt' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(1)
  })

  it('passes when no coordinates in cluster file', async () => {
    // Confirms this validation does not report false positive
    //
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_cluster.py#L21
    const file = createMockFile({ fileName: 'cluster_example.txt' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(0)
  })

  it('fails when coordinates in metadata file', async () => {
    // Confirms this validation does not report false negatives
    //
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_cell_metadata.py#L17
    const file = createMockFile({ fileName: 'metadata_bad_has_coordinates.txt' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata' })
    expect(errors).toHaveLength(1)
  })

  it('passes when no coordinates in metadata file', async () => {
    // Confirms this validation does not report false positives
    //
    // eslint-disable-next-line max-len
    // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/af1c124993f4a3e953debd5a594124f1ac52eee7/tests/test_cell_metadata.py#L31
    const file = createMockFile({ fileName: 'metadata_good_v2-0-0.txt' })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata' })
    expect(errors).toHaveLength(0)
  })

  it('renders validation message', async () => {
    const issues = {
      errors: [['error', 'foo:bar', 'Test error message']],
      warnings: [['warning', 'baz:moo', 'Test warning message']]
    }

    render(
      <ValidationMessage
        studyAccession={'SCP123'}
        issues={issues}
        fileName={'invalid_file.txt'}
        showRefreshLink={true}
      />
    )

    // Test UI
    // This displays OK in the UI, but not in the test.  Why?
    // const displayedError = screen.getByTestId('validation-error')
    // expect(displayedError).toHaveTextContent(errorMsgs[0])
    // expect(displayedError).toHaveTextContent('Refresh the page') // Sync-specific


    const displayedWarning = screen.getByTestId('validation-warning')
    expect(displayedWarning).toHaveTextContent(issues.warnings[0][2])
  })
})

// With the client side file validation feature flag set to false expect invalid files to pass
describe('Client-side file validation feature flag is false', () => {
  beforeEach(() => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        clientside_validation: false
      })
  })

  it('Does not catch missing headers in metadata file', async () => {
    const file = createMockFile({
      fileName: 'foo2.txt',
      content: 'NAME,biosample_id,CellID\nTYPE,numeric,numeric\nCELL_0001,id1,cell1'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Metadata', use_metadata_convention: true })
    expect(errors).toHaveLength(0)
  })

  it('Does not catch missing GENE header in expression matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo4.txt',
      content: 'IS_NOT_GENE,X,Y\nItm2a,0,5\nEif2b2,3,0\nPf2b2,1,9'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Expression Matrix' })
    expect(errors).toHaveLength(0)
  })

  it('Does not catch row with wrong number of columns in sparse matrix file', async () => {
    const file = createMockFile({
      fileName: 'foo6.mtx',
      content: '%%MatrixMarket matrix coordinate integer general\n%\n4 8 9\n4 3 0\n4 1'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'MM Coordinate Matrix' })
    expect(errors).toHaveLength(0)
  })

  it('Does not catch duplicate row values in barcodes file', async () => {
    const file = createMockFile({
      fileName: 'foo6.tsv',
      content: 'fake000\nfake001\nfake002\nfake000'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: '10X Barcodes File' })
    expect(errors).toHaveLength(0)
  })

  it('Does not catch  duplicate cell names in cluster file', async () => {
    const file = createMockFile({
      fileName: 'foo.txt',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCELL_0001,34.472,32.211\nCELL_0001,15.975,10.043'
    })
    const [{ errors }] = await validateLocalFile(file, { file_type: 'Cluster' })
    expect(errors).toHaveLength(0)
  })
}
)
