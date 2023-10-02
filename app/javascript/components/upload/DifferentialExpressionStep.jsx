import React, { useState, useEffect } from 'react'

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

/** A simple one-vs-rest only example for author DE file */
function OneVsRestOnlyExample({ headers, dePackage }) {
  if (dePackage === 'seurat') {
    // E.g. p_val, avg_log2FC, pct.1, pct.2, p_val_adj, cluster, gene
    return (
      <>
        <table className="table-terra de-example">
          <thead>
            <tr><td className="orange">{headers['size']}</td><td className="pink">{headers['significance']}</td><td className="optional">mean</td><td>{headers['group']}</td><td>{headers['gene']}</td><td>...</td></tr>
          </thead>
          <tbody>
            <tr><td>0.00049</td><td>0.00009</td><td>6.00312</td><td className="blue">A</td><td>It2ma</td><td>...</td></tr>
            <tr><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td className="blue">A</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
            <tr><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td className="green">B</td><td>It2ma</td><td>...</td></tr>
            <tr><td>0.00036</td><td>0.074825</td><td>12.71389</td><td className="green">B</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
          </tbody>
        </table>
        <p>
        Seurat can output one-vs-rest DE via <a href="https://satijalab.org/seurat/reference/findallmarkers" target="_blank"><code>FindAllMarkers</code></a>.
        </p>
      </>
    )
  } else {
    return (
      <>
        <table className="table-terra de-example">
          <thead>
            <tr><td>{headers['gene']}</td><td>{headers['group']}</td><td className="orange">{headers['size']}</td><td className="pink">{headers['significance']}</td><td className="optional">mean</td><td>...</td></tr>
          </thead>
          <tbody>
            <tr><td>It2ma</td><td className="blue">A</td><td>0.00049</td><td>0.00009</td><td>6.00312</td><td>...</td></tr>
            <tr><td>Sergef</td><td className="blue">A</td><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
            <tr><td>It2ma</td><td className="green">B</td><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td>...</td></tr>
            <tr><td>Sergef</td><td className="green">B</td><td>0.00036</td><td>0.074825</td><td>12.71389</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
          </tbody>
        </table>
        { dePackage === 'scanpy' &&
        <p>Scanpy can output one-vs-rest DE via <a href="https://scanpy-tutorials.readthedocs.io/en/latest/pbmc3k.html#Finding-marker-genes" target="_blank"><code>rank_gene_groups()</code></a>.</p>
        }
        {dePackage === 'other' &&
        <p>The format for uploaded DE files is flexible.  Just "Choose file" and refine headers below.</p>
        }
      </>
    )
  }
}

/** A one-vs-rest and pairwise example for author DE file */
function OneVsRestAndPairwiseExample({ headers, dePackage }) {
  if (dePackage === 'seurat') {
    // E.g. p_val, avg_log2FC, pct.1, pct.2, p_val_adj, cluster, gene
    return (
      <>
        <table className="table-terra de-example">
          <thead>
            <tr><td className="orange">{headers['size']}</td><td className="pink">{headers['significance']}</td><td className="optional">mean</td><td>{headers['group']}</td><td>comparison_group</td><td>{headers['gene']}</td><td>...</td></tr>
          </thead>
          <tbody>
            <tr><td>0.00049</td><td>0.00009</td><td>6.00312</td><td className="blue">A</td><td className="red">rest</td><td>It2ma</td><td>...</td></tr>
            <tr><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td className="blue">A</td><td className="red">rest</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
            <tr><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td className="green">B</td><td className="red">rest</td><td>It2ma</td><td>...</td></tr>
            <tr><td>0.00036</td><td>0.074825</td><td>12.71389</td><td className="green">B</td><td className="red">rest</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
            <tr><td>-0.10246</td><td>0.40019</td><td>0.41357</td><td className="blue">A</td><td className="green">B</td><td>It2ma</td><td>...</td></tr>
            <tr><td>0.00060</td><td>0.00005</td><td>1.82731</td><td className="blue">A</td><td className="green">B</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
            <tr><td>0.00249</td><td>0.00103</td><td>0.42130</td><td className="blue">A</td><td className="yellow">C</td><td>It2ma</td><td>...</td></tr>
            <tr><td>-0.00049</td><td>0.02648</td><td>1.06551</td><td className="blue">A</td><td className="yellow">C</td><td>Sergef</td><td>...</td></tr>
            <tr><td>...</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
          </tbody>
        </table>
        <p>
          Seurat can output one-vs-rest DE via <a href="https://satijalab.org/seurat/reference/findallmarkers" target="_blank"><code>FindAllMarkers</code></a>,
          which can be combined with pairwise DE output from <a href="https://satijalab.org/seurat/articles/de_vignette" target="_blank"><code>FindMarkers(..., ident.1="A", ident.2="B")</code></a>.
        </p>
      </>
    )
  } else {
    return (
      <>
        <table className="table-terra de-example">
          <thead>
            <tr><td>{headers['gene']}</td><td>{headers['group']}</td><td>comparison_group</td><td className="orange">{headers['size']}</td><td className="pink">{headers['significance']}</td><td className="optional">mean</td><td>...</td></tr>
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
        { dePackage === 'scanpy' &&
        <p>Scanpy can output one-vs-rest DE via <a href="https://scanpy-tutorials.readthedocs.io/en/latest/pbmc3k.html#Finding-marker-genes" target="_blank"><code>rank_gene_groups()</code></a>.</p>
        }
        {dePackage === 'other' &&
        <p>The format for uploaded DE files is flexible.  Just "Choose file" and refine headers below.</p>
        }
      </>
    )
  }
}

// TODO: Restore if there is interest in wide format
//
// /** A wide one-vs-rest and pairwise example for author DE file */
// function OneVsRestAndPairwiseWideExample({headers, dePackage}) {
//   return (
//     <>
//       <div className="de-example-wide-format">
//         <table className="table-terra de-example wide-format">
//           <colgroup>
//             <col className="col-genes" />
//             <col className="col-logfoldchanges" />
//             <col className="col-qval" />
//             <col className="col-mean" />
//             <col className="col-ellipsis" />
//             <col className="col-logfoldchanges" />
//             <col className="col-qval" />
//             <col className="col-mean" />
//             <col className="col-ellipsis" />
//             <col className="col-logfoldchanges" />
//             <col className="col-qval" />
//             <col className="col-mean" />
//             <col className="col-ellipsis" />
//             <col className="col-logfoldchanges" />
//             <col className="col-qval" />
//             <col className="col-mean" />
//             <col className="col-ellipsis" />
//           </colgroup>
//           <thead>
//             <tr><td>genes</td><td><span className="blue">A</span>--<span className="red">rest</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="red">rest</span>--pvals_adj</td><td><span className="blue">A</span>--<span className="red">rest</span>--<span className="optional">mean</span></td><td>...</td><td><span className="green">B</span>--<span className="red">rest</span>--logfoldchanges</td><td><span className="green">B</span>--<span className="red">rest</span>--pvals_adj</td><td><span className="green">B</span>--rest--<span className="optional">mean</span></td><td>...</td><td>A--<span className="green">B</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="green">B</span>--pvals_adj</td><td><span className="blue">A</span>--<span className="green">B</span>--<span className="optional">mean</span></td><td>...</td><td><span className="blue">A</span>--<span className="yellow">C</span>--logfoldchanges</td><td><span className="blue">A</span>--<span className="yellow">C</span>--pvals_adj</td><td><span className="blue">A</span>--<span className="yellow">C</span>--<span className="optional">mean</span></td><td>...</td></tr>
//           </thead>
//           <tbody>
//             <tr><td>It2ma</td><td>0.00049</td><td>0.00009</td><td>6.00312</td><td>...</td><td>-3.00246</td><td>0.00000</td><td>0.51128</td><td>...</td><td>-0.10246</td><td>0.40019</td><td>0.41357</td><td>...</td><td>0.00249</td><td>0.00103</td><td>0.42130</td><td>...</td></tr>
//             <tr><td>Sergef</td><td>-0.00036</td><td>0.00239</td><td>4.20466</td><td>...</td><td>0.00036</td><td>0.074825</td><td>12.71389</td><td>...</td><td>0.00060</td><td>0.00005</td><td>1.82731</td><td>...</td><td>-0.00049</td><td>0.02648</td><td>1.06551</td><td>...</td></tr>
//           </tbody>
//         </table>
//       </div>
//                 Wide format <i>does not</i> repeat values in the first column.  Long format is the default.
//       <br/><br/>
//       <p>Wide headers have the form <span className="code">&lt;group&gt;--&lt;comparison_group&gt;--&lt;metric&gt;</span>.</p>
//     </>
//   )
// }

const scanpyHeaders = {
  'gene': 'names',
  'group': 'group',
  'size': 'logfoldchanges',
  'significance': 'pvals_adj'
}

// E.g. p_val, avg_log2FC, pct.1, pct.2, p_val_adj, cluster, gene
const seuratHeaders = {
  'gene': 'gene',
  'group': 'cluster',
  'size': 'avg_log2FC',
  'significance': 'p_val_adj'
}

const otherHeaders = {
  'gene': 'gene',
  'group': 'group',
  'size': 'logfoldchange',
  'significance': 'qval'
}

const headersByPackage = {
  'scanpy': scanpyHeaders,
  'seurat': seuratHeaders,
  'other': otherHeaders
}

/** Tables of hypothetical author DE file excerpts, of various formats */
function ExampleTable({ comparison, dePackage, setComparison, setDePackage }) {
  /** Updates shown example's comparison type */
  function updateComparison(newComparison) {
    setComparison(newComparison)
  }

  /** Updates shown example's header dePackage */
  function updatePackage(newPackage) {
    setDePackage(newPackage)
  }

  const headers = headersByPackage[dePackage]

  return (
    <>
      <div>
        <p><b>Example DE file formats you can upload</b></p>
        <div>
          <span style={{ 'marginRight': '12px' }}>Package:</span>
          <label>
            <input type="radio" name="dePackage" style={{ 'position': 'relative', 'top': '1px', 'marginRight': '3px' }}
              onClick={() => updatePackage('scanpy')}
              checked={dePackage === 'scanpy'}
            />
                Scanpy
          </label>
          <label style={{ 'marginLeft': '20px' }}>
            <input type="radio" name="dePackage" style={{ 'position': 'relative', 'top': '1px', 'marginRight': '3px' }}
              onClick={() => updatePackage('seurat')}
            />
            Seurat
          </label>
          <label style={{ 'marginLeft': '20px' }}>
            <input type="radio" name="dePackage" style={{ 'position': 'relative', 'top': '1px', 'marginRight': '3px' }}
              onClick={() => updatePackage('other')}
            />
                Other
          </label>
        </div>
        <div style={{ 'marginBottom': '10px' }}>
          <span style={{ 'marginRight': '12px' }}>Comparisons:</span>
          <label>
            <input type="radio" name="comparison" style={{ 'position': 'relative', 'top': '1px', 'marginRight': '3px' }}
              onClick={() => updateComparison('one-vs-rest-only')}
              checked={comparison === 'one-vs-rest-only'}
            />
            One-vs-rest
          </label>
          <label style={{ 'marginLeft': '20px' }}>
            <input type="radio" name="comparison" style={{ 'position': 'relative', 'top': '1px', 'marginRight': '3px' }}
              onClick={() => updateComparison('one-vs-rest-and-pairwise')}
            />
                One-vs-rest and pairwise
          </label>
        </div>
        {comparison === 'one-vs-rest-only' &&
        <OneVsRestOnlyExample headers={headers} dePackage={dePackage} />
        }
        {comparison === 'one-vs-rest-and-pairwise' &&
        <>
          <OneVsRestAndPairwiseExample headers={headers} dePackage={dePackage} />
          {/* TODO: Restore if there is interest in wide format */}
          {/* <span>You can also use <span onClick={() => setComparison('one-vs-rest-and-pairwise-wide')}>wide format</span>.</span> */}
        </>
        }
        {/* TODO: Restore if there is interest in wide format */}
        {/* {comparison === 'one-vs-rest-and-pairwise-wide' &&
          <OneVsRestAndPairwiseWideExample headers={headers} />
        } */}
      </div>
    </>
  )
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
  const [comparison, setComparison] = useState('one-vs-rest-only')
  const [dePackage, setDePackage] = useState('scanpy')

  const menuOptions = serverState.menu_options

  const deFiles = formState.files.filter(differentialExpressionFileFilter)

  useEffect(() => {
    if (deFiles.length === 0) {
      addNewFile(DEFAULT_NEW_DE_FILE)
    }
  }, [deFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-5">
        <p className="form-terra">
          <p>
            Upload DE files to <b>enable <a href="https://singlecell.zendesk.com/hc/en-us/articles/6059411840027-Exploratory-differential-gene-expression-analysis" target="_blank">exploring differential gene expression</a></b> by the study variables where you have calculated differential expression.
            By adding your DE data here, you can enrich your study with custom DE analysis that goes beyond the limited SCP-computed DE results available by default.
          </p>
          <p>Simply <b>choose your DE file, adjust inferred headers if needed, and upload it</b>.  Or, select different "Package" and "Comparisons" options at right to see example formats for DE files that you can upload.
          Beyond metrics for size and significance, you can also include arbitrary other metrics, like "mean".  <b>Column headers can have any order, and any name</b>.</p>
          <p>Upload one DE file per annotation.  Append all DE gene rows for each comparison as shown at right.</p>
        </p>
      </div>
      <div className="col-md-7">
        <p className="form-terra">
          <div className="row" style={{ 'paddingLeft': '1em' }}>
            <ExampleTable
              dePackage={dePackage}
              comparison={comparison}
              setDePackage={setDePackage}
              setComparison={setComparison}
            />
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

    {/*
      Mitigates unintentionally hidden y-overflow when showing grouped options
      for select near bottom of page
    */}
    <div style={{ 'height': '250px' }}></div>
  </div>
}
