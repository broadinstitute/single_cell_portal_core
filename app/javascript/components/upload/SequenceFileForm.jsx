import React, { useEffect } from 'react'

import Select from '~/lib/InstrumentedSelect'
import FileUploadControl from './FileUploadControl'
import { TextFormField, SaveDeleteButtons } from './form-components'
import { SavingOverlay } from './ExpandableFileForm'
import { validateFile, FileTypeExtensions } from './upload-utils'

const REQUIRED_FIELDS = [{ label: 'species', propertyName: 'taxon_id' }]
const BAM_REQUIRED_FIELDS = REQUIRED_FIELDS.concat([{ label: 'Genome assembly', propertyName: 'genome_assembly_id' }])
const HUMAN_REQUIRED_FIELDS = REQUIRED_FIELDS.concat([
  { label: 'External link', propertyName: 'external_link_url' },
  { label: 'External link name', propertyName: 'name' }
])
const allowedFileExts = FileTypeExtensions.sequence

/** renders a form for editing/uploading a sequence file and any assoicated bundle files */
export default function SequenceFileForm({
  file,
  updateFile,
  allFiles,
  saveFile,
  deleteFile,
  addNewFile,
  sequenceFileTypes,
  fileMenuOptions,
  associatedIndexFile,
  bucketName
}) {
  const speciesOptions = fileMenuOptions.species.map(spec => ({ label: spec.common_name, value: spec.id }))
  const selectedSpecies = speciesOptions.find(opt => opt.value === file.taxon_id)
  let assemblyOptions = []
  if (selectedSpecies) {
    // filter the assemblies by the selected species
    assemblyOptions = fileMenuOptions.genome_assemblies
      .filter(ga => ga.taxon_id === selectedSpecies.value)
      .map(ga => ({ label: ga.name, value: ga.id }))
  }
  const selectedAssembly = assemblyOptions.find(opt => opt.value === file.genome_assembly_id)

  let requiredFields = REQUIRED_FIELDS
  if (file.human_data) {
    requiredFields = HUMAN_REQUIRED_FIELDS
  } else if (file.file_type === 'BAM') {
    requiredFields = BAM_REQUIRED_FIELDS
  }
  const validationMessages = validateFile({ file, allFiles, requiredFields, allowedFileExts })
  const humanTaxon = speciesOptions.find(opt => opt.label === 'human')

  return <div className="row top-margin" key={file._id}>
    <div className="col-md-12">
      <form id={`misc-file-form-${file._id}`}
        className="form-terra"
        onSubmit={e => e.preventDefault()}
        acceptCharset="UTF-8">
        <div className="form-group">
          <label>Primary Human Data?</label><br/>
          <label className="sublabel">
            <input type="radio"
              name={`sequenceHuman-${file._id}`}
              value="false"
              checked={!file.human_data}
              onChange={e => updateFile(file._id, { human_data: false, human_fastq_url: null })} />
              &nbsp;No
          </label>
          <label className="sublabel">
            <input type="radio"
              name={`sequenceHuman-${file._id}`}
              value="true" checked={file.human_data}
              onChange={e => updateFile(file._id, { human_data: true, file_type: 'Fastq', uploadSelection: null, taxon_id: humanTaxon.value })}/>
              &nbsp;Yes
          </label>
        </div>
        { !file.human_data && <>
          <div className="row">
            <div className="col-md-12">
              <FileUploadControl
                file={file}
                allFiles={allFiles}
                updateFile={updateFile}
                allowedFileExts={FileTypeExtensions.sequence}
                validationMessages={validationMessages}
                bucketName={bucketName}/>
            </div>
          </div>
          <div className="form-group">
            <label className="labeled-select">File type
              <Select options={sequenceFileTypes.map(ft => ({ label: ft, value: ft }))}
                data-analytics-name="sequence-file-type"
                value={{ label: file.file_type, value: file.file_type }}
                onChange={val => updateFile(file._id, { file_type: val.value })}/>
            </label>
          </div>
        </> }
        { file.human_data &&
          <div className="row">
            <div className="col-md-12">
              <TextFormField label="Link to primary human FASTQ file *"
                fieldName="human_fastq_url"
                file={file}
                updateFile={updateFile}/>
              <TextFormField label="Name *" fieldName="name" file={file} updateFile={updateFile}/>
            </div>
          </div>
        }

        <div className="form-group">
          <label className="labeled-select">Species *
            <Select options={speciesOptions}
              data-analytics-name="sequence-species-select"
              value={selectedSpecies}
              isDisabled={file.human_data}
              placeholder="Select one..."
              onChange={val => updateFile(file._id, { taxon_id: val.value })}/>
          </label>
        </div>
        { file.file_type === 'BAM' &&
          <div className="form-group">
            <label className="labeled-select">Genome Assembly *
              <Select options={assemblyOptions}
                data-analytics-name="sequence-assembly-select"
                value={selectedAssembly}
                placeholder="Select one..."
                onChange={val => updateFile(file._id, { genome_assembly_id: val.value })}/>
            </label>
          </div>
        }
        <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>

        <SaveDeleteButtons {...{ file, updateFile, saveFile, deleteFile, validationMessages }}/>
        { (file.file_type === 'BAM' && associatedIndexFile) &&
          <BamIndexFileForm parentFile={file}
            file={associatedIndexFile}
            allFiles={allFiles}
            updateFile={updateFile}
            saveFile={saveFile}
            deleteFile={deleteFile}
            addNewFile={addNewFile}
            bucketName={bucketName}/>
        }
        { (file.file_type === 'BED' && associatedIndexFile) &&
          <BedIndexFileForm parentFile={file}
            file={associatedIndexFile}
            allFiles={allFiles}
            updateFile={updateFile}
            saveFile={saveFile}
            deleteFile={deleteFile}
            addNewFile={addNewFile}
            bucketName={bucketName}/>
        }

      </form>

      <SavingOverlay file={file} updateFile={updateFile}/>
    </div>
  </div>
}

/** renders a control for uploading a BAM Index file */
function BamIndexFileForm({
  file,
  allFiles,
  parentFile,
  updateFile,
  saveFile,
  deleteFile,
  addNewFile,
  bucketName
}) {
  const validationMessages = validateFile({ file, allFiles, allowedFileExts: FileTypeExtensions.bai })

  // add an empty file to be filled in if none are there
  useEffect(() => {
    if (!file) {
      addNewFile({
        file_type: 'BAM Index',
        human_fastq_url: '',
        human_data: false,
        options: { bam_id: parentFile._id }
      })
    }
  }, [file])

  // if parent id changes, update the child bam_id pointer
  useEffect(() => {
    if (file && file.options.bam_id !== parentFile._id) {
      updateFile(file._id, { options: { bam_id: parentFile._id } })
    }
  }, [parentFile._id])

  if (!file) {
    return <span></span>
  }
  return <div className="row">
    <div className="col-md-12 ">
      <div className="sub-form">
        <h5>BAM index file</h5>
        <FileUploadControl
          file={file}
          allFiles={allFiles}
          updateFile={updateFile}
          allowedFileExts={FileTypeExtensions.bai}
          validationMessages={validationMessages}
          bucketName={bucketName}/>
        <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
        <SaveDeleteButtons
          file={file}
          updateFile={updateFile}
          saveFile={saveFile}
          deleteFile={deleteFile}
          validationMessages={validationMessages}/>
      </div>
      <SavingOverlay file={file} updateFile={updateFile}/>
    </div>
  </div>
}

/** renders a control for uploading a BAM Index file */
function BedIndexFileForm({
  file,
  allFiles,
  parentFile,
  updateFile,
  saveFile,
  deleteFile,
  addNewFile,
  bucketName
}) {
  const validationMessages = validateFile({ file, allFiles, allowedFileExts: FileTypeExtensions.tbi })

  // add an empty file to be filled in if none are there
  useEffect(() => {
    if (!file) {
      addNewFile({
        file_type: 'TBI',
        human_fastq_url: '',
        human_data: false,
        options: { bed_id: parentFile._id }
      })
    }
  }, [file])

  // if parent id changes, update the child bed_id pointer
  useEffect(() => {
    if (file && file.options.bed_id !== parentFile._id) {
      updateFile(file._id, { options: { bed_id: parentFile._id } })
    }
  }, [parentFile._id])

  if (!file) {
    return <span></span>
  }
  return <div className="row">
    <div className="col-md-12 ">
      <div className="sub-form">
        <h5>TBI file</h5>
        <FileUploadControl
          file={file}
          allFiles={allFiles}
          updateFile={updateFile}
          allowedFileExts={FileTypeExtensions.tbi}
          validationMessages={validationMessages}
          bucketName={bucketName}/>
        <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
        <SaveDeleteButtons
          file={file}
          updateFile={updateFile}
          saveFile={saveFile}
          deleteFile={deleteFile}
          validationMessages={validationMessages}/>
      </div>
      <SavingOverlay file={file} updateFile={updateFile}/>
    </div>
  </div>
}
