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
          <p>Upload differential expression (DE) files to enable users to compare genes by DE in cells grouped by type, disease, treatment, and other experimental conditions.  Use long or wide format, one file per annotation.  Comparisons can be one-vs-rest or pairwise.</p>
          In both formats, headers for "logfoldchanges" and "qval" are required; these let users see log<sub>2</sub>(fold change) and q-value, respectively.  Other metrics like "mean" are optional.
          <div className="row">
            <div className="col-md-12">
              <div className="col-sm-6 padded">
                <b>Long format</b>
                <table className="table-terra de-example">
                  <thead>
                    <tr><td>genes</td><td>group</td><td>comparison_group</td><td className="orange">logfoldchanges</td><td className="pink">qval</td><td className="optional">mean</td><td>...</td></tr>
                  </thead>
                  <tbody>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="red">rest</td><td>0.00049</td><td>0.00009</td><td>6.00312</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="red">rest</td><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="green">B</td><td className="red">rest</td><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="green">B</td><td className="red">rest</td><td>0.00036</td><td>0.074825</td><td>12.71389</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="green">B</td><td>-0.10246</td><td>0.40019</td><td>0.41357</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="green">B</td><td>0.00060</td><td>0.00005</td><td>1.82731</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                    <tr><td>It2ma</td><td className="blue">A</td><td className="yellow">C</td><td>0.00249</td><td>0.00103</td><td>0.42130</td><td>...</td></tr>
                    <tr><td>Sergef</td><td className="blue">A</td><td className="yellow">C</td><td>-0.00049</td><td>0.02648</td><td>1.06551</td><td>...</td></tr>
                    <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
                  </tbody>
                </table>
                Long format repeats values in the first column.
              </div>
              <div className="col-sm-6 padded de-example-wide-format" >
                <b>Wide format</b>
                <table className="table-terra de-example wide-format">
                  <colgroup>
                    <col className="col-genes" />
                    <col className="col-logfoldchanges" />
                    <col className="col-qval" />
                    <col className="col-mean" />
                    <col className="col-ellipsis" />
                    <col className="col-logfoldchanges" />
                    <col className="col-qval" />
                    <col className="col-mean" />
                    <col className="col-ellipsis" />
                    <col className="col-logfoldchanges" />
                    <col className="col-qval" />
                    <col className="col-mean" />
                    <col className="col-ellipsis" />
                    <col className="col-logfoldchanges" />
                    <col className="col-qval" />
                    <col className="col-mean" />
                    <col className="col-ellipsis" />
                  </colgroup>
                  <thead>
                    <tr><td>genes</td><td><span className="blue">A</span>--<span className="red">rest</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="red">rest</span>--qval</td><td><span className="blue">A</span>--<span className="red">rest</span>--mean</td><td>...</td><td><span className="green">B</span>--<span className="red">rest</span>--logfoldchanges</td><td><span className="green">B</span>--<span className="red">rest</span>--qval</td><td><span className="green">B</span>--rest--mean</td><td>...</td><td>A--<span className="green">B</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="green">B</span>--qval</td><td><span className="blue">A</span>--<span className="green">B</span>--mean</td><td>...</td><td><span className="blue">A</span>--<span className="yellow">C</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="yellow">C</span>--qval</td><td><span className="blue">A</span>--<span className="yellow">C</span>--mean</td><td>...</td></tr>
                  </thead>
                  <tbody>
                    <tr><td>It2ma</td><td>0.00049</td><td>0.00009</td><td>6.00312</td><td>...</td><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td>...</td><td>-0.10246</td><td>0.40019</td><td>0.41357</td><td>...</td><td>0.00249</td><td>0.00103</td><td>0.42130</td><td>...</td></tr>
                    <tr><td>Sergef</td><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td>...</td><td>0.00036</td><td>0.074825</td><td>12.71389</td><td>...</td><td>0.00060</td><td>0.00005</td><td>1.82731</td><td>...</td><td>-0.00049</td><td>0.02648</td><td>1.06551</td><td>...</td></tr>
                  </tbody>
                </table>
                "Wide format" <i>does not</i> repeat values in the first column.
                <br/><br/>
                <p>Wide headers have the form <span className="code">&lt;group&gt;--&lt;comparison_group&gt;--&lt;metric&gt;</span>.</p>
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
