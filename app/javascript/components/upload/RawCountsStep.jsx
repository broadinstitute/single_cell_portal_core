import React, { useEffect } from 'react'

import ExpressionFileForm from './ExpressionFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_RAW_COUNTS_FILE = {
  is_spatial: false,
  expression_file_info: {
    is_raw_counts: true,
    biosample_input_type: 'Whole cell',
    modality: 'Transcriptomic: unbiased',
    raw_counts_associations: []
  },
  file_type: 'Expression Matrix'
}

export const fileTypes = ['Expression Matrix', 'MM Coordinate Matrix']

export const rawCountsFileFilter = file => fileTypes.includes(file.file_type) &&
  file.expression_file_info?.is_raw_counts

export default {
  title: 'Raw count matrices',
  header: 'Raw count expression files',
  name: 'rawCounts',
  component: RawCountsUploadForm,
  fileFilter: rawCountsFileFilter
}

/** form for uploading a parent expression file and any children */
function RawCountsUploadForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const rawParentFiles = formState?.files.filter(rawCountsFileFilter)
  const fileMenuOptions = serverState?.menu_options

  useEffect(() => {
    if (rawParentFiles.length === 0) {
      addNewFile(DEFAULT_NEW_RAW_COUNTS_FILE)
    }
  }, [rawParentFiles.length])

  return <div>
    {getExpressionFileInfoMessage(isAnnDataExperience, 'Raw')}
    { (!isAnnDataExperience && rawParentFiles.length > 1) &&
      <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_RAW_COUNTS_FILE}/> }
    { rawParentFiles.map(file => {
      return <ExpressionFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        addNewFile={addNewFile}
        fileMenuOptions={fileMenuOptions}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={rawParentFiles.length === 1}
        isAnnDataExperience={isAnnDataExperience}/>
    })}
    {!isAnnDataExperience && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_RAW_COUNTS_FILE}/>}
  </div>
}

/**
 * Retrieve the expression file info message for when in classic upload mode
*/
export function getExpressionFileInfoMessage(isAnnDataExperience, expressionType) {
  if (!isAnnDataExperience) {
    let message = ''
    if (expressionType === 'Raw') {
      message = 'Raw count data enables data reuse in new analyses. Ideal raw count data is unfiltered, without normalization or other processing performed. Gene expression scores can be uploaded in either of two file types:'
    } else {
      message = 'Processed matrix data is used to support gene expression visualizations. Gene expression scores can be uploaded in either of two file types:'
    }

    return <div className="row">
      <div className="col-md-12">
        <div className="form-terra">
          <div className="row">
            <div className="col-md-12">
              <p>{message}</p>
            </div>
          </div>
          {expressionFileStructureHelp}
        </div>
      </div>
    </div>
  }
}

const expressionFileStructureHelp = <>
  <div className="row">
    <div className="col-sm-6 padded">
      <a href="https://raw.githubusercontent.com/broadinstitute/single_cell_portal/master/demo_data/expression_example.txt" target="_blank" rel="noreferrer noopener">Dense matrix</a>
      <pre>GENE&#09;CELL_1&#9;CELL_2&#09;CELL_3&#09;...<br/>It2ma&#09;0&#09;0&#09;0&#09;...<br/>Sergef&#09;0&#09;7.092&#09;0&#09;...<br/>Chil5&#09;0&#09;0&#09;0&#09;...<br/>Fgfr3&#09;0&#9;0&#09;0.978&#09;<br/>...</pre>
      A “Dense matrix” is a file (.txt, .tsv, or .csv)** that has a header row containing the value “GENE” in the first column, and single cell names in each successive column.
    </div>
    <div className="col-sm-6 padded" >
      <a href="https://github.com/broadinstitute/single_cell_portal_core/blob/master/test/test_data/GRCh38/matrix.mtx" target="_blank" rel="noreferrer noopener">Sparse matrix (.mtx)</a>
      <pre>%%MatrixMarket matrix coordinate real general<br/>%<br/>17123 31231 124124<br/>1 1241 1.0<br/>1 1552 2.0<br/>...</pre>
      A “Sparse matrix,” as seen in <a href="https://support.10xgenomics.com/single-cell-gene-expression/software/pipelines/latest/output/matrices" target="_blank" rel="noreferrer noopener">10x Genomics</a>
      , is a Matrix Market file (.mtx, .mm, or .txt)** that contains a sparse matrix in coordinate form.<br/>
      You&apos;ll be prompted for the&nbsp;
      <a href="https://kb.10xgenomics.com/hc/en-us/articles/115000794686-How-is-the-MEX-format-used-for-the-gene-barcode-matrices" target="_blank" rel="noreferrer noopener">features</a> and&nbsp;
      <a href="https://kb.10xgenomics.com/hc/en-us/articles/115000794686-How-is-the-MEX-format-used-for-the-gene-barcode-matrices" target="_blank" rel="noreferrer noopener">barcodes</a>
      &nbsp;files after selecting this type.
    </div>
  </div>

  <div className="row">
    <div className="col-md-12">
      <a href="https://www.gnu.org/software/gzip/manual/gzip.html" target="_blank" rel="noreferrer noopener">Gzipped</a>
      &nbsp;files of these types (e.g. .txt.gz) are accepted as well
    </div>
  </div>
</>
