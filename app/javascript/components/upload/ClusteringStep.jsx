import React, { useEffect } from 'react'

import ClusteringFileForm from './ClusteringFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_CLUSTER_FILE = {
  is_spatial: false,
  file_type: 'Cluster'
}

export const clusterFileFilter = file => file.file_type === 'Cluster' && !file.is_spatial

export default {
  title: 'Clustering',
  name: 'clustering',
  header: 'Clustering',
  component: ClusteringUploadForm,
  fileFilter: clusterFileFilter
}


/** Renders a form for uploading one or more cluster/spatial files */
export function ClusteringUploadForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const clusterFiles = formState.files.filter(clusterFileFilter)

  useEffect(() => {
    if (clusterFiles.length === 0) {
      addNewFile(DEFAULT_NEW_CLUSTER_FILE)
    }
  }, [clusterFiles.length])

  return <div>
    {!isAnnDataExperience && <span>
      <div className="row">
        <div className="col-md-12">
          <div className="form-terra">
            <div className="row">
              <div className="col-md-12">
                <p>A <a href="https://github.com/broadinstitute/single_cell_portal/blob/master/demo_data/cluster_example.txt" target="_blank" rel="noreferrer">cluster file</a> (.txt or .txt.gz) contains any cluster ordinations and optional cluster-specific metadata.</p>
              </div>
            </div>
            <div className="row">
              <div className="col-md-6">
                <pre>NAME&#09;X&#09;Y&#09;Z&#09;Category&#09;Intensity<br/>TYPE&#09;numeric&#09;numeric&#09;numeric&#09;group&#09;numeric<br/>CELL_0001&#09;34.472&#09;32.211&#09;60.035&#09;C&#09;0.719<br/>CELL_0002&#09;15.975&#09;10.043&#09;21.424&#09;B&#09;.904<br/>...</pre>
              </div>
            </div>
            <div className="row">
              <div className="col-md-6">
                <p><strong>At minimum </strong> a cluster file has:</p>
              </div>
            </div>
            <div className="row">
              <div className="col-md-9 col-lg-offset-2 col-md-offset-1">
                <ul>
                  <li>3 columns</li>
                  <li>A header row containing the value <strong>“NAME”, “X”, “Y”,</strong>
                optionally <strong>“Z”</strong>, and columns containing cell-level annotations
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
            </div>
            <div className="row">
              <p className="col-sm-12 text-center">Once your cluster file has been successfully
             ingested, additional representative subsamples of the full resolution data will be stored as well.
              <a href="https://singlecell.zendesk.com/hc/en-us/articles/360060610032-Cluster-File-Subsampling" target="_blank" rel="noreferrer"> Learn More <i className='fas fa-question-circle'></i></a>
              </p>
            </div>
            <div className="row">
              <p className="col-sm-12">* Group values are treated as literal strings, and numerics
              as floating-point numbers.</p>
            </div>
          </div>
        </div>
      </div>
      { clusterFiles.length > 1 && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_CLUSTER_FILE}/> }
    </span>}
    { clusterFiles.map(file => {
      return <ClusteringFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={clusterFiles.length === 1}
        isAnnDataExperience={isAnnDataExperience}
      />
    })}
    
    {!isAnnDataExperience && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_CLUSTER_FILE}/>}
  </div>
}
