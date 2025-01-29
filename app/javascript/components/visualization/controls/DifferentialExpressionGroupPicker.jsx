import React, { useState } from 'react'

import Select from '~/lib/InstrumentedSelect'
import { clusterSelectStyle } from '~/lib/cluster-utils'
import { newlineRegex } from '~/lib/validation/io'
import { fetchBucketFile } from '~/lib/scp-api'
import PlotUtils from '~/lib/plot'
const { getLegendSortedLabels } = PlotUtils


// https://stackoverflow.com/questions/37909134/nbsp-jsx-not-working
const blankSpace = '\u00A0' // How React JSX does &nbsp;

const basePath = '_scp_internal/differential_expression/'

// Value to show in menu if user has not selected a group for DE
const noneSelected = 'Select group'

/** Takes array of strings, converts it to list options suitable for react-select */
function getSimpleOptions(stringArray) {
  const assignLabelsAndValues = name => ({ label: name, value: name })
  return stringArray.map(assignLabelsAndValues)
}

/** to round to n decimal places */
function round(num, places) {
  const multiplier = Math.pow(10, places)
  return Math.round(num * multiplier) / multiplier
}

/**
 * Transform raw TSV text into array of differential expression gene objects
 */
export function parseDeFile(tsvText, isAuthorDe=false) {
  const deGenes = []
  const tsvLines = tsvText.split(newlineRegex)
  for (let i = 1; i < tsvLines.length; i++) {
    const tsvLine = tsvLines[i]

    if (tsvLine === '') {continue}
    const row = tsvLine.split('\t')

    let deGene

    if (isAuthorDe) {
      // Each element in this array is DE data for the gene in this row
      //
      // TODO: There are usually more columns than size (e.g. logfoldchanges)
      // and significance (e.g. pvals_adj) that may well be of interest.
      // However, we don't parse those here because there is no UI for them.
      // If we opt to build a UI for further metrics (e.g. pctNzGroup in Scanpy
      // / pct.1 in Seurat, etc.), we would need to order them canonically
      // across SCP-computed DE results and (Ingest Pipeline-processed) author
      // DE results.
      let [
        index, // eslint-disable-line
        name, size, significance
      ] = row

      if (isAuthorDe) {
        size = round(size, 3),
        significance = round(significance, 3)
      }

      deGene = {
        // TODO (SCP-5201): Show significant zeros, e.g. 0's to right of 9 in 0.900
        name,
        size,
        significance
      }
    } else {
      // names  scores  logfoldchanges  pvals pvals_adj pct_nz_group  pct_nz_reference
      const [
        index, // eslint-disable-line
        name, score, size, altSignificance, significance
      ] = row

      deGene = {
        // TODO (SCP-5201): Show significant zeros, e.g. 0's to right of 9 in 0.900
        name,
        size,
        significance
      }
    }

    Object.entries(deGene).forEach(([k, v]) => {
      // Cast numeric string values as floats
      if (k !== 'name') {
        deGene[k] = parseFloat(v)
      }
    })
    deGenes.push(deGene)
  }

  window.deGenes = deGenes
  return deGenes
}

/**
 * Fetch array of differential expression gene objects
 *
 * @param {String} bucketId Identifier for study's Google bucket
 * @param {String} deFilePath File path of differential expression file in Google bucket
 * @param {Boolean} isAuthorDe If requesting author-computed DE data
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
async function fetchDeGenes(bucketId, deFilePath, isAuthorDe=false) {
  const data = await fetchBucketFile(bucketId, deFilePath)
  const tsvText = await data.text()
  const deGenes = parseDeFile(tsvText, isAuthorDe)
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
    } else if (comparison === 'pairwise') {
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

/** List menu of groups available to select for DE comparison */
function GroupListMenu({
  groups, selectedGroups, updateSelectedGroups, setNote, isMenuB=false,
  hoverAllOthers, setHoverAllOthers
}) {

  if (isMenuB) {
    groups.unshift('rest')
  }

  const groupsIndex = isMenuB ? 1 : 0
  const otherGroupsIndex = isMenuB ? 0 : 1
  const otherMenuSelection = selectedGroups[otherGroupsIndex]

  return (
    <>
      {groups.map((group, i) => {
        // If this menu has a selected group and this group isn't it,
        // then disable this group
        const isInvalid = group === otherMenuSelection && isMenuB

        if (isInvalid) {return ''}

        const isMenuANull = selectedGroups[0] === null

        const isDisabled = isMenuANull && isMenuB
        const disabledClass = ''
        let noteClass = ''
        let noteText = ''
        let hoverClass = ''

        const isRest = group === 'rest'

        // TODO (SCP-): SCP API: Add DE availability status for annotation groups
        const isAvailable = isRest

        if (isMenuB) {
          if (!isDisabled) {
            if (isAvailable) {
              if (isRest) {
                noteText = 'All other groups'
              } else {
                noteText = blankSpace
              }
              noteClass = 'available'
            } else {
              noteText = 'Pick to enable'
              noteClass = 'not-yet-available'
            }
          }

          if (isDisabled) {
            noteText = 'Select a group in other menu'
            noteClass = 'disabled'
          }

          if (hoverAllOthers) {
            hoverClass = 'hover'
          }
        }

        let ariaLabel = ''
        if (isMenuB) {
          ariaLabel = (noteText[0].toUpperCase() + noteText.slice(1)).replaceAll('-', ' ')
        }
        const labelClass = `de-group-menu-item ${noteClass} ${disabledClass} ${hoverClass}`

        const menuName = `pairwise-menu${isMenuB && '-b'}`
        const id = `${menuName}-${i}`

        return (
          <label
            htmlFor={id}
            className={labelClass}
            aria-label={ariaLabel}
            onMouseEnter={() => {
              if (isMenuB) {
                setNote(noteText)
                if (isRest) {setHoverAllOthers(true)}
              }
            }}
            onMouseLeave={() => {
              if (isMenuB) {
                setNote(blankSpace)
                if (isRest) {setHoverAllOthers(false)}
              }
            }}
            key={i}
          >
            <input
              id={id}
              type="radio"
              className="pairwise-menu-input"
              name={menuName}
              style={{ marginRight: '4px' }}
              disabled={isDisabled}
              onChange={event => {
                const radio = event.target
                const isChecked = radio.checked
                const groupName = radio.parentElement.innerText
                const newSelectedGroups = [...selectedGroups]

                const newGroup = isChecked ? groupName : null
                if (groupsIndex === 0 && newGroup === selectedGroups[1]) {
                  newSelectedGroups[1] === null
                }

                newSelectedGroups[groupsIndex] = newGroup

                updateSelectedGroups(newSelectedGroups)
              }}
            ></input>
            {group}
          </label>
        )
      })}
    </>
  )
}

/** Pick groups of cells for pairwise differential expression (DE) */
export function PairwiseDifferentialExpressionGroupLists({
  deGenes, countsByLabelForDe
}) {
  const groups = getLegendSortedLabels(countsByLabelForDe)

  const [selectedGroups, setSelectedGroups] = useState([null, null])
  const [note, setNote] = useState(blankSpace)
  const [hoverAllOthers, setHoverAllOthers] = useState(false)

  /** Set new selection for DE groups to compare */
  function updateSelectedGroups(newSelectedGroups) {
    setSelectedGroups(newSelectedGroups)
  }

  return (
    <>
      <div className="differential-expression-picker">
        <div className="pairwise-menu">
          <p>Pick groups to compare.</p>
          <GroupListMenu
            groups={groups}
            selectedGroups={selectedGroups}
            updateSelectedGroups={updateSelectedGroups}
            hoverAllOthers={hoverAllOthers}
            setHoverAllOthers={setHoverAllOthers}
          />
        </div>
        <div className="vs-note pairwise-lists">vs. </div>
        <div className="pairwise-menu pairwise-menu-b">
          <p><i>{note}</i></p>
          <GroupListMenu
            groups={groups}
            selectedGroups={selectedGroups}
            updateSelectedGroups={updateSelectedGroups}
            setNote={setNote}
            isMenuB={true}
            hoverAllOthers={hoverAllOthers}
            setHoverAllOthers={setHoverAllOthers}
          />
        </div>
      </div>
      {deGenes && <><br/><br/></>}
    </>
  )
}

/** Pick groups of cells for pairwise differential expression (DE) */
export function PairwiseDifferentialExpressionGroupPicker({
  bucketId, clusterName, annotation, deGenes, deGroup, setDeGroup,
  setDeGenes, countsByLabelForDe, deObjects, setDeFilePath,
  deGroupB, setDeGroupB, hasOneVsRestDe, significanceMetric
}) {
  const groups = getLegendSortedLabels(countsByLabelForDe)

  const defaultGroupsB = []
  const [deGroupsB, setDeGroupsB] = useState(defaultGroupsB)

  /** Update table based on new group selection */
  async function updateTable(groupA, groupB) {
    let deOption
    let deFileName
    if (groupB === 'rest') {
      deOption = getMatchingDeOption(deObjects, groupA, clusterName, annotation)
      deFileName = deOption[1]
    } else {
      deOption = getMatchingDeOption(deObjects, groupA, clusterName, annotation, 'pairwise', groupB)
      deFileName = deOption[2]
    }

    const deFilePath = basePath + deFileName

    setDeFilePath(deFilePath)

    const isAuthorDe = true // SCP doesn't currently automatically compute pairwise DE
    const deGenes = await fetchDeGenes(bucketId, deFilePath, isAuthorDe)
    setDeGenes(deGenes)
  }

  /** Update group in differential expression picker */
  async function updateDeGroupA(newGroup) {
    setDeGroup(newGroup)
    const newGroupsB = groups.filter(group => {
      const deOption = getMatchingDeOption(deObjects, newGroup, clusterName, annotation, 'pairwise', group)
      return deOption !== undefined && deOption !== newGroup
    })
    let groupHasRest = false
    if (hasOneVsRestDe) {
      groupHasRest = getMatchingDeOption(deObjects, newGroup, clusterName, annotation)
      if (groupHasRest) {
        newGroupsB.unshift('rest')
      }
    }
    setDeGroupsB(newGroupsB)

    if (newGroup === deGroupB || deGroupB && deGroupB === 'rest' && !groupHasRest) {
      setDeGroupB(null) // Clear group B upon changing group A, if A === B
      setDeGenes(null)
      return
    }

    if (deGroupB) {
      updateTable(newGroup, deGroupB)
    }
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
            className="differential-expression-pairwise de-group-select"
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
            className="differential-expression-pairwise de-group-select"
            value={{
              label: !deGroupB ? noneSelected : deGroupB,
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
export function OneVsRestDifferentialExpressionGroupPicker({
  bucketId, clusterName, annotation, deGenes, deGroup, setDeGroup, setDeGenes,
  countsByLabelForDe, deObjects, setDeFilePath, isAuthorDe
}) {
  let groups = getLegendSortedLabels(countsByLabelForDe)
  groups = groups.filter(group => {
    const deOption = getMatchingDeOption(deObjects, group, clusterName, annotation)
    return deOption !== undefined
  })

  /** Update group in differential expression picker */
  async function updateDeGroup(newGroup) {
    setDeGroup(newGroup)

    const deOption = getMatchingDeOption(deObjects, newGroup, clusterName, annotation)
    const deFileName = deOption[1]

    const deFilePath = basePath + deFileName

    setDeFilePath(deFilePath)

    const deGenes = await fetchDeGenes(bucketId, deFilePath, isAuthorDe)

    setDeGroup(newGroup)
    setDeGenes(deGenes)
  }

  const containerClass = deGenes ? 'differential-expression-picker' : 'flexbox-align-center flexbox-column'

  return (
    <>
      <div className={containerClass}>
        {!deGenes && <p>Compare one group to the rest.</p>}
        <Select
          defaultMenuIsOpen={!deGenes}
          options={getSimpleOptions(groups)}
          data-analytics-name="de-group-select"
          className="one-vs-rest-select"
          value={{
            label: deGroup === null ? noneSelected : deGroup,
            value: deGroup
          }}
          onChange={newGroup => updateDeGroup(newGroup.value)}
          styles={clusterSelectStyle}
        />
        {deGenes && <><span className="vs-note">vs. rest</span><br/><br/></>}
      </div>
    </>
  )
}
