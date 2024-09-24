import React from 'react'
import { render, screen, cleanup, fireEvent, waitForElementToBeRemoved, waitFor } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import { StudyContext } from 'components/upload/upload-utils'
import FileUploadControl from 'components/upload/FileUploadControl'
import { fireFileSelectionEvent } from '../lib/file-mock-utils'
import fetch from 'node-fetch'
import { setMetricsApiMockFlag } from 'lib/metrics-api'
import { getTokenExpiry } from './upload-wizard-test-utils'

describe('file upload control defaults the name of the file', () => {
  beforeAll(() => {
    global.fetch = fetch
    setMetricsApiMockFlag(true)
    window.SCP = {
      readOnlyTokenObject: {
        'access_token': 'test',
        'expires_in': 3600, // 1 hour in seconds
        'expires_at': getTokenExpiry()
      },
      readOnlyToken: 'test'
    }
  })
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })


  it('updates the name of the selected file', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Other'
    }
    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render(
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    )

    expect(screen.getByRole('button')).toHaveTextContent('Choose file')
    expect(screen.queryByTestId('file-name-validation')).toBeNull()

    const fileObj = fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster.txt',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenLastCalledWith('123', {
      uploadSelection: fileObj,
      name: 'cluster.txt',
      upload_file_name: 'cluster.txt'
    })
  })
})

it('updates the file upload name but preserves custom name', async () => {
  const file = {
    _id: '123',
    name: 'previousName',
    status: 'new',
    file_type: 'Cluster'
  }
  const updateFileHolder = { updateFile: () => {} }
  const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

  render(
    <StudyContext.Provider value={{ accession: 'SCP123' }}>
      <FileUploadControl
        file={file}
        allFiles={[file]}
        updateFile={updateFileHolder.updateFile}
        allowedFileExts={['.txt']}
        validationMessages={{}}/>
    </StudyContext.Provider>
  )

  expect(screen.getByRole('button')).toHaveTextContent('Choose file')
  expect(screen.queryByTestId('file-name-validation')).toBeNull()

  const fileObj = fireFileSelectionEvent(screen.getByTestId('file-input'), {
    fileName: 'cluster.txt',
    content: 'NAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
  })
  await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
  expect(updateFileSpy).toHaveBeenLastCalledWith('123', {
    uploadSelection: fileObj,
    name: 'previousName',
    upload_file_name: 'cluster.txt'
  })
})

describe('file upload control validates the selected file', () => {
  it('validates the extension', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Other'
    }

    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))

    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster.foo',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenCalledTimes(0)
    expect(screen.getByTestId('validation-error')).toHaveTextContent('after correcting cluster.foo')
    expect(screen.getByTestId('validation-error')).toHaveTextContent('Allowed extensions are .txt')
  })

  it('validates the name uniqueness', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Other'
    }

    const otherFile = {
      _id: '567',
      name: 'cluster.txt'
    }

    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file, otherFile]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))

    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster.txt',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenCalledTimes(0)
    expect(screen.getByTestId('validation-error')).toHaveTextContent('after correcting cluster.txt')
    expect(screen.getByTestId('validation-error'))
      .toHaveTextContent('A file named cluster.txt already exists in your study')
  })

  it('validates the name uniqueness across upload selections', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Other'
    }

    const otherFile = {
      _id: '567',
      uploadSelection: { name: 'cluster1.txt' }
    }

    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file, otherFile]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))

    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster1.txt',
      content: 'NAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenCalledTimes(0)
    expect(screen.getByTestId('validation-error'))
      .toHaveTextContent('A file named cluster1.txt already exists in your study')
  })

  it('validates the content', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Cluster'
    }

    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))

    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster.txt',
      content: 'notNAME,X,Y\nTYPE,numeric,numeric\nCell1,1,0\n'
    }, true)
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenCalledTimes(0)
    expect(screen.getByTestId('validation-error')).toHaveTextContent('after correcting cluster.txt')
    expect(screen.getByTestId('validation-error'))
      .toHaveTextContent('First row, first column must be "NAME" (case insensitive). Your value was "notNAME')
  })

  it('renders multiple content errors', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Cluster'
    }

    const updateFileHolder = { updateFile: () => {} }
    const updateFileSpy = jest.spyOn(updateFileHolder, 'updateFile')

    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          updateFile={updateFileHolder.updateFile}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))

    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: 'cluster.txt',
      content: 'notNAME,X,Y\nfoo,numeric,numeric\nCell1,1,0\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(updateFileSpy).toHaveBeenCalledTimes(0)
    expect(screen.getByTestId('validation-error')).toHaveTextContent('after correcting cluster.txt')
    expect(screen.getByTestId('validation-error'))
      .toHaveTextContent('First row, first column must be "NAME" (case insensitive). Your value was "notNAME')
    expect(screen.getByTestId('validation-error'))
      .toHaveTextContent('Second row, first column must be "TYPE" (case insensitive). Your value was "foo"')
  })

  it('shows the file chooser button appropriately', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Cluster'
    }
    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))
    expect(screen.queryAllByText('Choose file')).toHaveLength(1)
    cleanup()

    const file2 = {
      _id: '123',
      name: 'cluster.txt',
      status: 'new',
      file_type: 'Cluster',
      upload_file_name: 'cluster.txt'
    }
    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file2}
          allFiles={[file2]}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))
    expect(screen.queryAllByText('Replace')).toHaveLength(1)
    cleanup()

    const file3 = {
      _id: '123',
      name: 'cluster.txt',
      upload_file_name: 'cluster.txt',
      status: 'uploaded',
      file_type: 'Cluster'
    }
    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file3}
          allFiles={[file3]}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))
    expect(screen.queryAllByText('Choose file')).toHaveLength(0)
    expect(screen.queryAllByText('Replace')).toHaveLength(0)
  })

  it('shows the bucket path field when selected', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Cluster'
    }
    const { container } = render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          allowedFileExts={['.txt']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))
    expect(screen.queryAllByText('Use bucket path')).toHaveLength(1)
    const bucketToggle = screen.getByText('Use bucket path')
    fireEvent.click(bucketToggle)
    expect(container.querySelector('#remote_location-input-123')).toBeVisible()
  })

  it('validates file extension on bucket path entries', async () => {
    const file = {
      _id: '123',
      name: '',
      status: 'new',
      file_type: 'Cluster'
    }
    render((
      <StudyContext.Provider value={{ accession: 'SCP123' }}>
        <FileUploadControl
          file={file}
          allFiles={[file]}
          allowedFileExts={['.tsv']}
          validationMessages={{}}/>
      </StudyContext.Provider>
    ))
    expect(screen.queryAllByText('Use bucket path')).toHaveLength(1)
    const bucketToggle = screen.getByText('Use bucket path')
    fireEvent.click(bucketToggle)
    const bucketPathInput = screen.getByTestId('remote-location-input')
    expect(bucketPathInput).toBeVisible()
    fireEvent.change(bucketPathInput, { target: { value: 'bad.pdf' } })
    expect(bucketPathInput).toHaveValue('bad.pdf')
    await waitFor(() => {
      expect(screen.getByTestId('validation-error')).toBeInTheDocument()
      expect(screen.getByText('Allowed extensions are .tsv')).toBeVisible()
    })
  })
})
