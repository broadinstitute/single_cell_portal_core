/**
 * @fileoverview Tests for client-side file validation (CSFV) for sync
 */
import fetch, { Headers } from 'node-fetch'
import '@testing-library/jest-dom'

import ValidateFile from 'lib/validation/validate-file'

const { validateRemoteFile, MAX_SYNC_CSFV_BYTES, getSizeProps } = ValidateFile

const bucketName = 'broad-singlecellportal-public'

describe('Client-side file validation for sync', () => {
  beforeAll(() => {
    global.fetch = fetch
    global.Headers = Headers
  })

  it('sends range request for remote file', async () => {
    const fakeLog = jest.spyOn(global, 'fetch')
    fakeLog.mockImplementation(() => { })

    window.SCP = {
      readOnlyToken: 'test'
    }

    const fileName =
        encodeURIComponent('test/DATA_MATRIX_LOG_TPM_mismatch_columns.txt')
    const fileType = 'Expression Matrix'
    const fileOptions = {}

    try {
      await validateRemoteFile(
        bucketName, fileName, fileType, fileOptions
      )
    } catch (error) {
      // Pass over.  Throws error due to inconsistency between `node-fetch`
      // and browser fetch handling of range responses.
      error
    }

    // This file actually exists at the URL.  It might be useful for a later
    // integration test, which would be more robust to internal refactoring,
    // and more precise (sensitive/specific) of a test.
    const expectedUrl =
        'https://storage.googleapis.com/download/storage/v1/b/' +
        'broad-singlecellportal-public/o/' +
        'test%252FDATA_MATRIX_LOG_TPM_mismatch_columns.txt?alt=media'

    expect(global.fetch).toHaveBeenCalledWith(
      expectedUrl,
      {
        headers: new Headers({
          'Range': [`bytes=0-${MAX_SYNC_CSFV_BYTES}`],
          'Authorization': ['Bearer test']
        }),
        method: 'GET'
      }
    )
  })

  it('gets sizeProps for logging', async () => {
    const size = 213832273
    const contentRange = `bytes 0-${MAX_SYNC_CSFV_BYTES}/${size}`
    const contentLength = '52428801'
    const content = 'e'.repeat(parseInt(contentLength))

    const file = new File([content], 'many-e.txt', { type: 'plain/text' })
    const sizeProps = getSizeProps(contentRange, contentLength, file)

    const expectedSizeProps = {
      'fileSizeFetched': parseInt(contentLength),
      'fileSizeTotal': size,
      'fetchedCompleteFile': false
    }

    expect(sizeProps).toEqual(expectedSizeProps)
  })
})
