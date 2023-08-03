import React, { useEffect } from 'react'

import { AddFileButton } from './form-components'
import DifferentialExpressionFileForm from './DifferentialExpressionFileForm'


const DEFAULT_NEW_DE_FILE = {
  file_type: 'Differential Expression',
  differential_expression_file_info: {
    clustering_association: undefined,
    computational_method: undefined,
    annotation_name: undefined,
    annotation_scope: undefined
  }
}

export const differentialExpressionFileFilter = file => file.file_type === 'Differential Expression'

export default {
  title: 'Differential expression',
  name: 'differential expression',
  header: 'Differential expression',
  component: DifferentialFileUploadForm,
  fileFilter: differentialExpressionFileFilter
}

/** Renders a form for uploading differential expression files */
export function DifferentialFileUploadForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience,
  annotationsAvailOnStudy
}) {
  const menuOptions = serverState.menu_options

  const deFiles = formState.files.filter(differentialExpressionFileFilter)

  useEffect(() => {
    if (deFiles.length === 0) {
      addNewFile(DEFAULT_NEW_DE_FILE)
    }
  }, [deFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
          Upload a file with differential expression for a particular clustering and annotation.  (Either format, note auto-detection.  Use tables themed like pre to align columns.  Move tab to top of other files.)
          <div className="row">
            <div className="col-md-12">
              <div className="col-sm-6 padded">
                <b>Long format</b>
                <table className="table-terra de-example" style={{ 'background': '#EEE', 'fontFamily': 'Menlo, Monaco, Consolas, "Courier New", monospace' }}>
                  <thead>
                    <tr><td>genes</td><td>group</td><td>comparison_group</td><td>logfoldchanges</td><td>qval</td><td>mean</td><td>...</td></tr>
                  </thead>
                  <tbody>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="red">rest</td><td>0.00049</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="red">rest</td><td>-0.00036</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="yellow">B</td><td className="red">rest</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="yellow">B</td><td className="red">rest</td><td>0.00036</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="yellow">B</td><td>-0.10246</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="yellow">B</td><td>0.00060</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="green">C</td><td>0.00249</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="green">C</td><td>-0.00049</td><td>0.00009</td><td>12.00009</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                  </tbody>
                </table>
                "Long format" has values that repeat in the first column.
              </div>
              <div className="col-sm-6 padded" >
                <b>Wide format</b>
                {/* <pre>
                  genes</td><td>A--rest--logfoldchanges</td><td>A--rest--qval</td><td>A--rest--mean</td><td>B--rest--logfoldchanges</td><td>B--rest--qval</td><td>B--rest--mean</td><td>...</td><td>A--B--logfoldchanges</td><td>A--B--qval</td><td>A--B--mean</td><td>A--C--logfoldchanges</td><td>A--C--qval</td><td>A--C--mean</td><td>...<br/>
                  It2ma</td><td>A</td><td>rest</td><td>0.00049</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td><br/>
                  Sergef</td><td>A</td><td>rest</td><td>-0.00036</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td><br/>
                  Chil5</td><td>A</td><td>rest</td><td>2.95114</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td>...</td><td>-3.00246</td><td>0.00009</td><td>12.00009</td><td><br/>
                </pre> */}
                "Wide format" has values that <i>do not</i> repeat in the first column.
              </div>
            </div>
          </div>
        </p>
      </div>
    </div>
    { deFiles.map(file => {
      return <DifferentialExpressionFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        annDataFileTypes={['AnnData']}
        bucketName={formState.study.bucket_id}
        annotationsAvailOnStudy={annotationsAvailOnStudy}
        isInitiallyExpanded={deFiles.length === 1}
        menuOptions={menuOptions}/>
    })}

    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_DE_FILE}/>
  </div>
}


