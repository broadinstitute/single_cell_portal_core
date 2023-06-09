import React, { useState } from 'react'

import Select from '~/lib/InstrumentedSelect'
import { clusterSelectStyle } from '~/lib/cluster-utils'
import { newlineRegex } from '~/lib/validation/io'
import { fetchBucketFile } from '~/lib/scp-api'
import PlotUtils from '~/lib/plot'
const { getLegendSortedLabels } = PlotUtils

const basePath = '_scp_internal/differential_expression/'

// Value to show in menu if user has not selected a group for DE
const noneSelected = 'Select group'

/** Takes array of strings, converts it to list options suitable for react-select */
function getSimpleOptions(stringArray) {
  const assignLabelsAndValues = name => ({ label: name, value: name })
  return stringArray.map(assignLabelsAndValues)
}

/**
 * Transform raw TSV text into array of differential expression gene objects
 */
function parseDeFile(tsvText) {
  const deGenes = []
  const tsvLines = tsvText.split(newlineRegex)
  for (let i = 1; i < tsvLines.length; i++) {
    const tsvLine = tsvLines[i]
    if (tsvLine === '') {continue}
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
 * @param {String} deFilePath File path of differential expression file in Google bucket
 *
 * @return {Array} deGenes Array of DE gene objects, each with properties:
 *   name: Gene name
 *   score: Differential expression score assigned by Scanpy.
 *   log2FoldChange: Log-2 fold change.  How many times more expression (1 = 2, 2 = 4, 3 = 8).
 *   pval: p-value.  Statistical significance of the `score` value.
 *   pvalAdj: Adjusted p-value.  p-value adjusted with Benjamini-Hochberg FDR correction
 *   pctNzGroup: Percent non-zero, group.  % of cells with non-zero expression in selected group.
 *   pctNzReference: Percent non-zero, reference.  % of cells with non-zero expression in non-selected groups.
 **/
async function fetchDeGenes(bucketId, deFilePath) {
  const data = await fetchBucketFile(bucketId, deFilePath)
  const tsvText = await data.text()
  const deGenes = parseDeFile(tsvText)
  return deGenes
}

/** Gets matching deObject for the given group and cluster + annot combo */
function getMatchingDeOption(
  deObjects, group, clusterName, annotation, comparison='one_vs_rest', groupB=null
) {
  const deObject = deObjects.find(deObj => {
    return (
      deObj.cluster_name === clusterName &&
      deObj.annotation_name === annotation.name &&
      deObj.annotation_scope === annotation.scope
    )
  })

  const matchingDeOption = deObject.select_options[comparison].find(option => {
    if (comparison === 'one_vs_rest') {
      return option[0] === group
    } else {
      // Pairwise comparison.  Naturally sort group labels, as only
      // naturally-sorted option is available, since combinations are not
      // ordered and we don't want to pass and store 2x the data.
      const [groupASorted, groupBSorted] = [group, groupB].sort((a, b) => {
        return a[0].localeCompare(b[0], 'en', { numeric: true, ignorePunctuation: true })
      })
      return option[0] === groupASorted && option[1] === groupBSorted
    }
  })

  return matchingDeOption
}

/** Pick groups of cells for pairwise differential expression (DE) */
export function PairwiseDifferentialExpressionGroupPicker({
  bucketId, clusterName, annotation, deGenes, deGroup, setDeGroup,
  setDeGenes, countsByLabel, deObjects, setDeFilePath,
  deGroupB, setDeGroupB
}) {
  const groups = getLegendSortedLabels(countsByLabel)

  const deGroupsA = groups.filter(group => {
    const deOption = getMatchingDeOption(deObjects, group, clusterName, annotation)
    return deOption !== undefined
  })

  const [deGroupsB, setDeGroupsB] = useState(
    deGroupsA.filter(group => !!deGroup && group !== deGroup)
  )

  // console.log('deGroupsA', deGroupsA)
  // console.log('deGroupsB', deGroupsB)
  // console.log('defaultBGroups', defaultBGroups)
  // console.log('deObjects', deObjects)

  /** Update table based on new group selection */
  async function updateTable(groupA, groupB) {
    console.log('in updateTable, groupB', groupB)
    const deOption = getMatchingDeOption(deObjects, groupA, clusterName, annotation, 'pairwise', groupB)
    console.log('deOption', deOption)
    const deFileName = deOption[2]

    const deFilePath = basePath + deFileName

    setDeFilePath(deFilePath)

    const deGenes = await fetchDeGenes(bucketId, deFilePath)
    setDeGenes(deGenes)
  }

  /** Update group in differential expression picker */
  async function updateDeGroupA(newGroup) {
    setDeGroup(newGroup)
    setDeGroupsB(
      deGroupsA.filter(group => group !== newGroup)
    )

    if (newGroup === deGroupB) {
      setDeGroupB(null) // Clear group B upon changing group A
      return
    }

    updateTable(newGroup, deGroupB)
  }

  /** Update group in differential expression picker */
  async function updateDeGroupB(newGroup) {
    setDeGroupB(newGroup)

    updateTable(deGroup, newGroup)
  }

  return (
    <>
      <div className="differential-expression-picker">
        {!deGenes && <p>Compare one group to another.</p>}
        <div className="pairwise-select">
          <Select
            defaultMenuIsOpen={!deGenes}
            options={getSimpleOptions(groups)}
            data-analytics-name="de-group-select-a"
            value={{
              label: deGroup === null ? noneSelected : deGroup,
              value: deGroup
            }}
            onChange={newGroup => updateDeGroupA(newGroup.value)}
            styles={clusterSelectStyle}
          />
        </div>
        <span className="vs-note">vs. </span>
        <div className="pairwise-select pairwise-select-b">
          <Select
            options={getSimpleOptions(deGroupsB)}
            data-analytics-name="de-group-select-b"
            value={{
              label: deGroupB === null ? noneSelected : deGroupB,
              value: deGroupB
            }}
            onChange={newGroup => updateDeGroupB(newGroup.value)}
            styles={clusterSelectStyle}
          />
        </div>
      </div>
      {deGenes && <><br/><br/></>}
    </>
  )
}

/** Pick groups of cells for one-vs-rest-only differential expression (DE) */
export function DifferentialExpressionGroupPicker({
  bucketId, clusterName, annotation, deGenes, deGroup, setDeGroup, setDeGenes,
  countsByLabel, deObjects, setDeFilePath
}) {
  let groups = getLegendSortedLabels(countsByLabel)
  groups = groups.filter(group => {
    const deOption = getMatchingDeOption(deObjects, group, clusterName, annotation)
    return deOption !== undefined
  })

  /** Update group in differential expression picker */
  async function updateDeGroup(newGroup) {
    setDeGroup(newGroup)

    const deOption = getMatchingDeOption(deObjects, newGroup, clusterName, annotation)
    const deFileName = deOption[1]

    const basePath = '_scp_internal/differential_expression/'
    const deFilePath = basePath + deFileName

    setDeFilePath(deFilePath)

    const deGenes = await fetchDeGenes(bucketId, deFilePath)

    setDeGroup(newGroup)
    setDeGenes(deGenes)
  }

  return (
    <>
      {!deGenes &&
        <div className="flexbox-align-center flexbox-column">
          <span>Compare one group to the rest.</span>
          <Select
            defaultMenuIsOpen
            options={getSimpleOptions(groups)}
            data-analytics-name="de-group-select"
            value={{
              label: deGroup === null ? noneSelected : deGroup,
              value: deGroup
            }}
            onChange={newGroup => updateDeGroup(newGroup.value)}
            styles={clusterSelectStyle}
          />
        </div>
      }
      {deGenes &&
      <div className="differential-expression-picker">
        <div className="one-vs-rest-select">
          <Select
            options={getSimpleOptions(groups)}
            data-analytics-name="de-group-select"
            value={{
              label: deGroup === null ? noneSelected : deGroup,
              value: deGroup
            }}
            onChange={newGroup => updateDeGroup(newGroup.value)}
            styles={clusterSelectStyle}
          />
        </div>
        <span className="vs-note">vs. rest</span>
        <br/>
        <br/>
      </div>
      }
    </>
  )
}
