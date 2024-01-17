import { validateFile } from 'components/upload/upload-utils'

describe('upload file validation name checks', () => {
  it('allows files with unique names and valid extensions', async () => {
    const file = {
      status: 'new',
      name: 'foo.txt',
      uploadSelection: { name: 'foo.txt' },
      _id: '10'
    }

    const allFiles = [{
      status: 'uploaded',
      name: 'bar.txt',
      _id: '11'
    }, file]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt'] })
    expect(msgs.fileName).toEqual(undefined)
  })

  it('disallows files with duplicate names', async () => {
    const file = {
      status: 'new',
      name: 'bar.txt',
      isDirty: true,
      uploadSelection: { name: 'whatever.txt' },
      _id: '10'
    }
    const allFiles = [{
      status: 'uploaded',
      name: 'bar.txt',
      _id: '11'
    }, file]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt'] })
    expect(msgs.fileName).toEqual('A file named bar.txt already exists in your study')
  })


})

describe('upload file validation new file checks', () => {
  it('requires a file selected to be uploaded', async () => {
    const file = {
      status: 'new',
      name: 'unique',
      _id: '10'
    }
    const allFiles = [{
      status: 'uploaded',
      name: 'special',
      upload_file_name: 'bar.txt',
      _id: '11'
    }, file]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt'] })
    expect(msgs.uploadSelection).toEqual('You must select a file to upload or specify a remote file')
  })

  it('checks required file extensions', async () => {
    const file = {
      status: 'new',
      name: 'unique',
      uploadSelection: { name: 'bar.txt33' },
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt'] })
    expect(msgs.fileName).toEqual('Allowed extensions are .txt')
  })

  it('checks required file extensions are at the end of the file', async () => {
    const file = {
      status: 'new',
      name: 'unique',
      uploadSelection: { name: 'f.txt.bar' },
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt', '.txt.gz'] })
    expect(msgs.fileName).toEqual('Allowed extensions are .txt .txt.gz')
  })

  it('requires a bundle parent to be saved first', async () => {
    const file = {
      status: 'new',
      name: 'cluster labels',
      options: {
        cluster_file_id: 'newFile-1'
      },
      _id: '10'
    }
    const allFiles = [{
      status: 'new',
      name: 'Cluster A',
      _id: 'newFile-1'
    }, file]
    const msgs = validateFile({ file, allFiles, allowedFileExts: ['.txt'] })
    expect(msgs.parentSaved).toEqual('Parent file must be saved first')
  })
})

describe('it checks presence of required fields', () => {
  it('passes if required fields are present', async () => {
    const file = {
      name: 'unique',
      taxon_id: '1345',
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({
      file, allFiles, allowedFileExts: ['.txt', '.txt.gz'],
      requiredFields: [{ label: 'species', propertyName: 'taxon_id' }]
    })
    expect(msgs.taxon_id).toEqual(undefined)
  })

  it('fails if required fields are not present', async () => {
    const file = {
      status: 'new',
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({
      file, allFiles, allowedFileExts: ['.txt', '.txt.gz'],
      requiredFields: [{ label: 'species', propertyName: 'taxon_id' }]
    })
    expect(msgs.taxon_id).toEqual('You must specify: species')
  })

  it('messages both if multiple required fields are not present', async () => {
    const file = {
      name: 'unique',
      taxon_id: null,
      genome_assembly_id: null,
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({
      file, allFiles, allowedFileExts: ['.txt', '.txt.gz'],
      requiredFields: [{ label: 'species', propertyName: 'taxon_id' },
        { label: 'genome assembly', propertyName: 'genome_assembly_id' }]
    })
    expect(msgs.taxon_id).toEqual('You must specify: species')
    expect(msgs.genome_assembly_id).toEqual('You must specify: genome assembly')
  })

  it('handles validating nested properties', async () => {
    const file = {
      name: 'unique',
      expression_file_info: {
        biosample_input_type: null,
        units: 'Whole cell'
      },
      _id: '10'
    }
    const allFiles = [{ file }]
    const msgs = validateFile({
      file, allFiles, allowedFileExts: ['.txt', '.txt.gz'],
      requiredFields: [{ label: 'units', propertyName: 'expression_file_info.units' },
        { label: 'biosample input type', propertyName: 'expression_file_info.biosample_input_type' }]
    })
    expect(msgs['expression_file_info.units']).toEqual(undefined)
    expect(msgs['expression_file_info.biosample_input_type']).toEqual('You must specify: biosample input type')
  })
})
