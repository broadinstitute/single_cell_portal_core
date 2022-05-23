import React, { useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'

import Select from '~/lib/InstrumentedSelect'
import { clusterSelectStyle } from '~/lib/cluster-utils'
import { newlineRegex } from '~/lib/validation/io'
import { fetchBucketFile } from '~/lib/scp-api'

// Value to show in menu if user has not selected a group for DE
const noneSelected = 'Select a group'

/** Takes array of strings, converts it to list options suitable for react-select */
function getSimpleOptions(stringArray) {
  const assignLabelsAndValues = name => ({ label: name, value: name })
  return [{ label: noneSelected, value: '' }].concat(stringArray.map(assignLabelsAndValues))
}

const nonAlphaNumericRegex = /\W/g

/**
 * Transform raw TSV text into array of differential expression gene objects
 */
function parseDeFile(tsvText) {
  const deGenes = []
  const tsvLines = tsvText.split(newlineRegex)
  for (let i = 1; i < tsvLines.length; i++) {
    // Each element in this array is DE data for the gene in this row
    const [
      index, // eslint-disable-line
      name, score, log2FoldChange, pval, pvalAdj, pctNzGroup, pctNzReference
    ] = tsvLines[i].split('\t')
    const deGene = {
      score, log2FoldChange, pval, pvalAdj, pctNzGroup, pctNzReference
    }
    Object.entries(deGene).forEach(([k, v]) => {
      // Cast numeric string values as floats
      deGene[k] = parseFloat(v)
    })
    deGene.name = name
    deGenes.push(deGene)
  }

  return deGenes
}

/**
 * Fetch array of differential expression gene objects
 *
 * @param {String} bucketId Identifier for study's Google bucket
 * @param {String} deFileName Name of differential expression file
 * @param {Integer} numGenes Number of genes to include in returned deGenes array
 *
 * @return {Array} deGenes Array of DE gene objects, each with properties:
 *   name: Gene name
 *   score: Differential expression score assigned by Scanpy.
 *   log2FoldChange: Log-2 fold change.  How many times more expression (1 = 2, 2 = 4, 3 = 8).
 *   pval: p-value.  Statistical significance of the `score` value.
 *   pvalAdj: Adjusted p-value.  p-value adjusted for false discovery rate (FDR).
 *   pctNzGroup: Percent non-zero, group.  % of cells with non-zero expression in selected group.
 *   pctNzReference: Percent non-zero, reference.  % of cells with non-zero expression in non-selected groups.
 **/
async function fetchDeGenes(bucketId, deFileName, numGenes=20) {
  const deFilePath = `_scp-internal/differential-expression/${deFileName}`.replaceAll('/', '%2F')

  // TODO (SCP-4321): Perhaps refine logic for fetching file from bucket, e.g. perhaps add
  //  token parameter to fetchFileFromBucket
  const data = await fetchBucketFile(bucketId, deFilePath)
  const tsvText = await data.text()
  const deGenes = parseDeFile(tsvText)

  return deGenes.slice(0, numGenes)
}

/** Pick groups of cells for differential expression (DE) */
export default function DeGroupPicker({
  exploreInfo, setShowDeGroupPicker, setDeGroup, setDeGenes
}) {
  const annotation = exploreInfo?.annotationList?.default_annotation
  const groups = annotation?.values ?? []

  const [group, setGroup] = useState(noneSelected)

  /** Update group in DE picker */
  async function updateDeGroup() {
    const bucketId = exploreInfo?.bucketId

    // TODO (SCP-4321): Incorporate any updates to this general file name structure
    // <cluster_name>--<annotation_name>--<group_name>--<annotation_scope>--<method>.tsv
    const deFileName = `${[
      exploreInfo?.annotationList?.default_cluster,
      annotation.name,
      group,
      'wilcoxon'
    ]
      .map(s => s.replaceAll(nonAlphaNumericRegex, '_'))
      .join('--') }.tsv`

    const deGenes = await fetchDeGenes(bucketId, deFileName)

    setDeGroup(group)
    setDeGenes(deGenes)

    setShowDeGroupPicker(false)
  }

  // TODO (SCP-4321): Replace modal with dropdown at top of DE panel at right
  // TODO (SCP-4321): Move ← icon to left
  return (
    <Modal
      id='de-group-picker-modal'
      onHide={() => setShowDeGroupPicker(false)}
      show={true}
      animation={false}
      bsSize='small'>
      <Modal.Body>
        <div className="flexbox-align-center flexbox-column">
          <span>Choose a group to compare to all other groups</span>
          <Select
            options={getSimpleOptions(groups)}
            data-analytics-name="de-group-select"
            value={{
              label: group === '' ? noneSelected : group,
              value: group
            }}
            onChange={newGroup => setGroup(newGroup.value)}
            styles={clusterSelectStyle}
          />
        </div>
      </Modal.Body>
      <Modal.Footer>
        <button className="btn btn-primary" onClick={() => {updateDeGroup()}}>OK</button>
        <button className="btn terra-btn-secondary" onClick={() => setShowDeGroupPicker(false)}>Cancel</button>
      </Modal.Footer>
    </Modal>
  )
}