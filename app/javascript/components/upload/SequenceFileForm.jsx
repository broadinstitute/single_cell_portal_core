import React, { useEffect } from 'react'

import Select from '~/lib/InstrumentedSelect'
import FileUploadControl from './FileUploadControl'
import { TextFormField, SaveDeleteButtons } from './form-components'
import { SavingOverlay } from './ExpandableFileForm'
import { validateFile, FileTypeExtensions } from './upload-utils'

const REQUIRED_FIELDS = [{ label: 'species', propertyName: 'taxon_id' }]
const TRACK_REQUIRED_FIELDS = REQUIRED_FIELDS.concat([{ label: 'Genome assembly', propertyName: 'genome_assembly_id' }])
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
  } else if (['BAM', 'BED'].includes(file.file_type)) {
    requiredFields = TRACK_REQUIRED_FIELDS
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
          <label>Primary human data?</label><br/>
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
        { ['BAM', 'BED'].includes(file.file_type) &&
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

        { (['BAM', 'BED'].includes(file.file_type) || associatedIndexFile) &&
          <IndexFileForm
            parentFile={file}
            file={associatedIndexFile}
            allFiles={allFiles}
            updateFile={updateFile}
            saveFile={saveFile}
            deleteFile={deleteFile}
            addNewFile={addNewFile}
            bucketName={bucketName}
          />
        }

      </form>

      <SavingOverlay file={file} updateFile={updateFile}/>
    </div>
  </div>
}

/** renders a control for uploading a BAM Index or Tab Index file */
function IndexFileForm({
  file,
  allFiles,
  parentFile,
  updateFile,
  saveFile,
  deleteFile,
  addNewFile,
  bucketName
}) {
  let indexFileType = 'BAM Index'
  let optionsIdField = 'bam_id'
  let displayName = 'BAM'
  let extension = 'bai'
  if (parentFile.file_type == 'BED') {
    indexFileType = 'Tab Index'
    optionsIdField = 'bed_id'
    displayName = 'Tab'
    extension = 'tbi'
  }


  const validationMessages = validateFile({ file, allFiles, allowedFileExts: FileTypeExtensions.bai })

  // add an empty file to be filled in if none are there
  useEffect(() => {
    if (!file) {
      const newFile = {
        file_type: indexFileType,
        human_fastq_url: '',
        human_data: false,
        options: {}
      }
      newFile.options[optionsIdField] = parentFile._id
      addNewFile(newFile)
    }
  }, [file])

  // if parent id changes, update the child bam_id pointer
  useEffect(() => {
    if (file && file.options[optionsIdField] !== parentFile._id) {
      const updatedFields = { options: {} }
      updatedFields.options[optionsIdField] = parentFile._id
      updateFile(file._id, updatedFields)
    }
  }, [parentFile._id])

  if (!file) {
    return <span></span>
  }
  return <div className="row">
    <div className="col-md-12 ">
      <div className="sub-form">
        <h5>{displayName} index file</h5>
        <FileUploadControl
          file={file}
          allFiles={allFiles}
          updateFile={updateFile}
          allowedFileExts={FileTypeExtensions[extension]}
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
