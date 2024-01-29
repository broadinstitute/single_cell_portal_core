import React, { useEffect } from 'react'

import SequenceFileForm from './SequenceFileForm'
import { findBundleChildren } from './upload-utils'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_SEQUENCE_FILE = {
  file_type: 'Fastq',
  human_fastq_url: '',
  human_data: false,
  options: {}
}

const sequenceFileTypes = ['BAM', 'Fastq']
const sequenceFileFilter = file => sequenceFileTypes.includes(file.file_type)

export default {
  title: 'Sequence files',
  header: 'Sequence files',
  name: 'sequence',
  component: SequenceForm,
  fileFilter: sequenceFileFilter
}

/** Renders a form for uploading one or more sequence files */
function SequenceForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile
}) {
  const sequenceFiles = formState.files.filter(sequenceFileFilter)

  useEffect(() => {
    if (sequenceFiles.length === 0) {
      addNewFile(DEFAULT_NEW_SEQUENCE_FILE)
    }
  }, [sequenceFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <div className="form-terra">
          Primary sequence information, such as BAM, BAM Index, and FASTQ files<br />
          <p>
            <b>Non-human data</b><br />
            If you have a few, small (under 2 GB) non-human sequence files, they can be uploaded here.
            For uploading many or larger files, please refer to the instructions in
            our <a href="https://singlecell.zendesk.com/hc/en-us/articles/360061006011" target="_blank" rel="noopener noreferrer">documentation</a>.
          </p>
          <p>
            If you already have the gcloud CLI installed (Sept 2022 release or later) you can upload files directly using the following command:
          </p>
          <pre>
            gcloud storage cp /path/to/files gs://{formState.study.bucket_id}
          </pre>
          <p>
            <b>Primary human data</b><br />
            Primary sequence data derived from humans should be stored in other biological databases and can be linked here
            by selecting &apos;Yes&apos; for &apos;Primary Human Data&apos; and then providing a link in the text field.
          </p>
        </div>
      </div>
    </div>
    {sequenceFiles.length > 1 && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_SEQUENCE_FILE} />}
    {sequenceFiles.map(file => {
      const associatedBaiFile = findBundleChildren(file, formState.files)[0]
      return <SequenceFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        addNewFile={addNewFile}
        deleteFile={deleteFile}
        sequenceFileTypes={sequenceFileTypes}
        fileMenuOptions={serverState.menu_options}
        associatedBaiFile={associatedBaiFile}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={sequenceFiles.length === 1} />
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_SEQUENCE_FILE} />
  </div>
}
