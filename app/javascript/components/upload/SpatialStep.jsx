import React, { useEffect } from 'react'

import ClusteringFileForm from './ClusteringFileForm'
import { clusterFileFilter } from './ClusteringStep'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_SPATIAL_FILE = {
  is_spatial: true,
  file_type: 'Cluster'
}

export const spatialFileFilter = file => file.file_type === 'Cluster' && file.is_spatial

export default {
  title: 'Spatial transcriptomics',
  name: 'spatial',
  header: 'Spatial transcriptomics',
  component: SpatialUploadForm,
  fileFilter: spatialFileFilter
}


/** Renders a form for uploading one or more cluster/spatial files */
export function SpatialUploadForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile
}) {
  const spatialFiles = formState.files.filter(spatialFileFilter)
  const associatedClusterFileOptions = formState.files.filter(clusterFileFilter)
    .map(file => ({ label: file.name, value: file._id }))

  /** handle a change in the associated cluster select */
  function updateCorrespondingClusters(file, val) {
    let newVal = []
    if (val) {
      newVal = val.map(opt => opt.value)
    }
    updateFile(file._id, { spatial_cluster_associations: newVal })
  }

  useEffect(() => {
    if (spatialFiles.length === 0) {
      addNewFile(DEFAULT_NEW_SPATIAL_FILE)
    }
  }, [spatialFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <div className="form-terra">
          <div className="row">
            <div className="col-md-12">
              <p>
                A <a href="https://github.com/broadinstitute/single_cell_portal/blob/main/demo_data/spatial_example.txt" target="_blank" rel="noreferrer">spatial file</a>
                &nbsp;(.txt or .txt.gz) contains <a href="https://en.wikipedia.org/wiki/Spatial_transcriptomics" target="_blank" rel="noreferrer">spatial transcriptomics</a> cell coordinates and optional metadata.
              </p>
            </div>
          </div>
          <div className="row">
            <div className="col-md-6">
              <pre>NAME&#09;X&#09;Y&#09;Z&#09;Category&#09;Intensity<br/>TYPE&#09;numeric&#09;numeric&#09;numeric&#09;group&#09;numeric<br/>CELL_0001&#09;34.472&#09;32.211&#09;60.035&#09;C&#09;0.719<br/>CELL_0002&#09;15.975&#09;10.043&#09;21.424&#09;B&#09;.904<br/>...</pre>
            </div>
          </div>
          <div className="row">
            <div className="col-md-6">
              <p><strong>At minimum </strong> a spatial file has:</p>
            </div>
          </div>
          <div className="row">
            <div className="col-md-9 col-lg-offset-2 col-md-offset-1">
              <ul>
                <li>3 columns</li>
                <li>A header row containing the value <strong>“NAME”, “X”,
                “Y”,</strong> optionally <strong>“Z”</strong>, and columns containing cell-level annotations
                </li>
                <li>A second row with:</li>
                <ul >
                  <li>The header of <strong>“TYPE”</strong>to declare metadata types (see below).</li>
                  <li>A value for each metadata column declaring its datatype
                  </li>
                  <ul>
                    <li>The two accepted values are <strong>“group”</strong> (set membership)
                    or <strong>“numeric”</strong> (continuous scores).*</li>
                    <li>The values for the “X”, “Y”, and “Z” columns must be set to “numeric”.</li>
                  </ul>
                </ul>
              </ul>
            </div>

            <p className="col-sm-12 text-center">Once your spatial file has been successfully ingested,
            additional representative subsamples of the full resolution data will be stored as well.
            <a href="https://singlecell.zendesk.com/hc/en-us/articles/360060610032-Cluster-File-Subsampling" target="_blank" rel="noreferrer"> Learn More <i className='fas fa-question-circle'></i></a>
            </p>
          </div>
          <div className="row">
            <p className="col-sm-12">* Group values are treated as literal strings,
            and numerics as floating-point numbers.</p>
          </div>
        </div>
      </div>
    </div>
    { spatialFiles.length > 1 && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_SPATIAL_FILE}/> }
    { spatialFiles.map(file => {
      return <ClusteringFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        associatedClusterFileOptions={associatedClusterFileOptions}
        updateCorrespondingClusters={updateCorrespondingClusters}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={spatialFiles.length === 1}/>
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_SPATIAL_FILE}/>
  </div>
}
