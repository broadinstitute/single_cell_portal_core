import React, { useEffect } from 'react'

import CoordinateLabelFileForm from './CoordinateLabelFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_LABEL_FILE = {
  file_type: 'Coordinate Labels',
  options: {}
}

const coordinateLabelFileFilter = file => file.file_type === 'Coordinate Labels'

export default {
  title: 'Coordinate labels',
  name: 'coordinateLabels',
  header: 'Coordinate labels',
  component: CoordinateLabelForm,
  fileFilter: coordinateLabelFileFilter
}

/** Renders a form for uploading one or more cluster/spatial files */
function CoordinateLabelForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const coordinateFiles = formState.files.filter(coordinateLabelFileFilter)
  const associatedClusterFileOptions = formState.files.filter(f => f.file_type === 'Cluster')
    .map(file => ({ label: file.name, value: file._id }))

  /** handle a change in the associated cluster select */
  function updateCorrespondingClusters(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { options: { cluster_file_id: newVal } })
  }

  useEffect(() => {
    if (coordinateFiles.length === 0) {
      addNewFile(DEFAULT_NEW_LABEL_FILE)
    }
  }, [coordinateFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <div className="form-terra">
          <p>
            A <a href="https://raw.githubusercontent.com/broadinstitute/single_cell_portal/master/demo_data/coordinate_labels_example.txt" target="_blank" rel="noopener noreferrer">Coordinate Label File</a>
            &nbsp;specifies labels to display at specified coordinates of a cluster.
          </p>
          <pre>
            X&#09;Y&#09;Z&#09;LABELS<br/>
            35.47&#09;33.21&#09;61.03&#09;Region 1<br/>
            -10.68&#09;-52.64&#09;-57.34&#09;Region 2<br/>
            ...
          </pre>
          <p>
            <strong>These are not cluster files</strong> - they are annotations to overlay on top of a scatter plot.<br/>
            The file must be a plain text (.txt) file with at least 3 columns and a header
            row containing the values <strong>X</strong>, <strong>Y</strong>, and <strong>LABELS</strong>.
            The file may have an optional column of <strong>Z</strong> (for 3d clusters).
            The last column must contain text labels to display at the specified coordinates.
          </p>
          <p><i className="fas fa-fw fa-exclamation-triangle text-warning"></i> The coordinates of the labels
            must fall inside the ranges of the cluster they are associated with for them to render.</p>
        </div>
      </div>
    </div>
    { coordinateFiles.length > 1 && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_LABEL_FILE}/> }
    { coordinateFiles.map(file => {
      return <CoordinateLabelFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        associatedClusterFileOptions={associatedClusterFileOptions}
        updateCorrespondingClusters={updateCorrespondingClusters}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={coordinateFiles.length === 1}
        isAnnDataExperience={isAnnDataExperience}
      />
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_LABEL_FILE}/>
  </div>
}
