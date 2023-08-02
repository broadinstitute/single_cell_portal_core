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
                <pre>
                  genes&#09;group&#09;comparison_group&#09;logfoldchanges&#09;qval&#09;mean&#09;...<br/>
                  It2ma&#09;A&#09;rest&#09;0.00049&#09;0.00009&#09;12.00009&#09;...<br/>
                  Sergef&#09;A&#09;rest&#09;-0.00036&#09;0.00009&#09;12.00009&#09;...<br/>
                  Chil5&#09;A&#09;rest&#09;2.95114&#09;0.00009&#09;12.00009&#09;...<br/>
                  ...<br/>
                  It2ma&#09;B&#09;rest&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...<br/>
                  Sergef&#09;B&#09;rest&#09;0.00036&#09;0.00009&#09;12.00009&#09;...<br/>
                  Chil5&#09;B&#09;rest&#09;0.00329&#09;0.00009&#09;12.00009&#09;...<br/>
                  ...<br/>
                  It2ma&#09;A&#09;B&#09;-0.10246&#09;0.00009&#09;12.00009&#09;...<br/>
                  Sergef&#09;A&#09;B&#09;0.00060&#09;0.00009&#09;12.00009&#09;...<br/>
                  Chil5&#09;A&#09;B&#09;14.00309&#09;0.00009&#09;12.00009&#09;...<br/>
                  ...<br/>
                  It2ma&#09;A&#09;C&#09;0.00249&#09;0.00009&#09;12.00009&#09;...<br/>
                  Sergef&#09;A&#09;C&#09;-0.00049&#09;0.00009&#09;12.00009&#09;...<br/>
                  Chil5&#09;A&#09;C&#09;1.30079&#09;0.00009&#09;12.00009&#09;...<br/>
                  ...
                </pre>
                "Long format" has values that repeat in the first column.
              </div>
              <div className="col-sm-6 padded" >
                <b>Wide format</b>
                <pre>
                  genes&#09;A--rest--logfoldchanges&#09;A--rest--qval&#09;A--rest--mean&#09;B--rest--logfoldchanges&#09;B--rest--qval&#09;B--rest--mean&#09;...&#09;A--B--logfoldchanges&#09;A--B--qval&#09;A--B--mean&#09;A--C--logfoldchanges&#09;A--C--qval&#09;A--C--mean&#09;...<br/>
                  It2ma&#09;A&#09;rest&#09;0.00049&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;<br/>
                  Sergef&#09;A&#09;rest&#09;-0.00036&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;<br/>
                  Chil5&#09;A&#09;rest&#09;2.95114&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;...&#09;-3.00246&#09;0.00009&#09;12.00009&#09;<br/>
                </pre>
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


