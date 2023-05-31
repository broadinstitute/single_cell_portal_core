import React, { useEffect } from 'react'

import GeneListFileForm from './GeneListFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_GENE_LIST_FILE = {
  file_type: 'Gene List',
  heatmap_file_info: {
    custom_scaling: false,
    color_min: -1,
    color_max: 1
  },
  options: {}
}

const geneListFileFilter = file => file.file_type === 'Gene List'

export default {
  title: 'Precomputed heatmaps',
  header: 'Precomputed heatmaps',
  name: 'geneLists',
  component: GeneListForm,
  fileFilter: geneListFileFilter
}

/** Renders a form for uploading one or more miscellaneous files */
function GeneListForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const geneListFiles = formState.files.filter(geneListFileFilter)

  useEffect(() => {
    if (geneListFiles.length === 0) {
      addNewFile(DEFAULT_NEW_GENE_LIST_FILE)
    }
  }, [geneListFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <div className="form-terra">
          <p>
            A list of genes and any computed expression values (mean, median, etc.) across any clusters, for visualization as a heatmap.
          </p>
          <pre>
            GENE NAMES&#9;Cluster1&#9;Cluster2<br/>Grm2&#9;6.39&#9;1.96<br/>C1ql3&#9;6.66&#9;2.05
          </pre>
          <p>
            The file must be tab- or comma-delimited plain text (.txt) with the value &quot;GENE NAMES&quot; in the first column, and cluster names in each successive column.
            <br/>
            <a href="https://raw.githubusercontent.com/broadinstitute/single_cell_portal/master/demo_data/marker_gene_list_example.txt" target="_blank" rel="noreferrer noopener">
              Example file
            </a>
            <br/>
            By default, the dropdown name for these files is "Precomputed heatmaps".
            Customize that dropdown name in "View options" of <a href={`/single_cell/study/${formState.study.accession}#study-settings`} target="_blank">study settings</a><br/><br/>
            See <a href=" https://singlecell.zendesk.com/hc/en-us/articles/360061006291" target="_blank">full documentation</a> here for more information on display and customization.
          </p>
        </div>
      </div>
    </div>
    { geneListFiles.length > 1 && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_GENE_LIST_FILE}/> }
    { geneListFiles.map(file => {
      return <GeneListFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={geneListFiles.length === 1}
        isAnnDataExperience={isAnnDataExperience}
        />
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_GENE_LIST_FILE}/>
  </div>
}
