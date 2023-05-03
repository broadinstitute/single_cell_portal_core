
import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faArrowLeft, faDownload, faSearch, faTimes } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'

import DifferentialExpressionModal from '~/components/explore/DifferentialExpressionModal'
import DifferentialExpressionGroupPicker from '~/components/visualization/controls/DifferentialExpressionGroupPicker'

import {
  logDifferentialExpressionTableSearch,
  logSearchFromDifferentialExpression
} from '~/lib/search-metrics'
import { downloadBucketFile } from '~/lib/scp-api'


/** Return selected annotation object, including its `values` a.k.a. groups */
function getAnnotationObject(exploreParamsWithDefaults, exploreInfo) {
  const selectedAnnotation = exploreParamsWithDefaults?.annotation
  return exploreInfo.annotationList.annotations.find(thisAnnotation => {
    return (
      thisAnnotation.name === selectedAnnotation.name &&
      thisAnnotation.type === selectedAnnotation.type &&
      thisAnnotation.scope === selectedAnnotation.scope
    )
  })
}

/** Set up radio buttons to be all unchecked upon changing dropdown value */
function initChecked(deGenes, checkedGene) {
  const checked = {}
  if (!deGenes) {return checked}
  deGenes.forEach(deGene => {
    checked[deGene.name] = checkedGene && checkedGene === deGene.name
  })
  return checked
}

function DownloadButton({ bucketId, deFilePath }) {
  return (
    <a className="de-download-button"
      onClick={async () => {await downloadBucketFile(bucketId, deFilePath)}}
      data-analytics-name="differential-expression-download"
      data-toggle="tooltip"
      data-original-title="Download all DE genes data for this group"
    >
      <FontAwesomeIcon icon={faDownload}/>
    </a>
  )
}

function DifferentialExpressionTable({
  genesToShow, searchGenes, checked, clusterName, annotation, species, changeRadio
}) {
  return (
    <>
      <table className="de-table table table-terra table-scp-compact">
        <thead>
          <tr>
            <th>Name</th>
            <th>
              <span className="glossary" data-toggle="tooltip" data-original-title="Log (base 2) of fold change">
              log<sub>2</sub>(FC)
              </span>
            </th>
            <th>
              <span className="glossary" data-toggle="tooltip" data-original-title="p-value adjusted with Benjamini-Hochberg FDR correction">
              Adj. p-value
              </span>
            </th>
          </tr>
        </thead>
        <tbody>
          {genesToShow.map((deGene, i) => {
            return (
              <tr className="de-gene-row" key={i}>
                <td>
                  <label
                    title="Click to view gene expression.  Arrow down (↓) and up (↑) to quickly scan."
                  ><input
                      type="radio"
                      checked={checked[deGene.name]}
                      data-analytics-name="selected-gene-differential-expression"
                      value={deGene.name}
                      onClick={event => {
                        searchGenes([deGene.name])

                        // Log this search to Mixpanel
                        const rank = i
                        logSearchFromDifferentialExpression(
                          event, deGene, species, rank,
                          clusterName, annotation.name
                        )

                        changeRadio(event)
                      }}/>
                    {deGene.name}</label></td>
                <td>{deGene.log2FoldChange}</td>
                <td>{deGene.pvalAdj}</td>
              </tr>)
          })}
        </tbody>
      </table>
      <a href="https://forms.gle/qPGH5J9oFkurpbD76" target="_blank" title="Take a 1 minute survey">
      Help improve this new feature
      </a>
    </>
  )
}

/** Differential expression panel shown at right in Explore tab */
export default function DifferentialExpressionPanel({
  deGroup, deGenes, searchGenes,
  exploreInfo, exploreParamsWithDefaults, setShowDeGroupPicker, setDeGenes, setDeGroup,
  countsByLabel, numRows=15
}) {
  const clusterName = exploreParamsWithDefaults?.cluster
  const bucketId = exploreInfo?.bucketId
  const annotation = getAnnotationObject(exploreParamsWithDefaults, exploreInfo)
  const deObjects = exploreInfo?.differentialExpression

  const delayedDETableLogTimeout = useRef(null)

  // filter text for searching the legend
  const [genesToShow, setGenesToShow] = useState(deGenes)
  const [searchedGene, setSearchedGene] = useState('')

  const [checked, setChecked] = useState(initChecked(deGenes))
  const [deFilePath, setDeFilePath] = useState(null)

  const species = exploreInfo?.taxonNames

  /** Check radio button such that changing group unchecks all buttons */
  function changeRadio(event) {
    const newChecked = initChecked(deGenes, event.target.value)
    setChecked(newChecked)
  }

  /** Handle a user pressing the 'x' to clear the field */
  function handleClear() {
    updateSearchedGene('', 'clear')
    setGenesToShow(deGenes.slice(0, numRows))
  }

  /** Only show clear button if text is entered in search box */
  const showClear = searchedGene !== ''

  function updateSearchedGene(newSearchedGene, trigger) {
    setSearchedGene(newSearchedGene)

    // Log search on DE table after 1 second since last change
    // This prevents logging "searches" on "P", "T", "E", and "N" if
    // the string "PTEN" is typed in a speed plausible for someone who
    // knows they want to search PTEN, without stopping to explore interstitial
    // results in the DE table.
    clearTimeout(delayedDETableLogTimeout.current)
    delayedDETableLogTimeout.current = setTimeout(() => {
      const otherProps = { trigger }
      const genes = [newSearchedGene]
      logDifferentialExpressionTableSearch(genes, species, otherProps)
    }, 1000)
  }

  /** Update genes in table based on what user searches */
  useEffect(() => {
    let filteredGenes
    if (searchedGene === '') {
      filteredGenes = deGenes
    } else {
      const lowerCaseSearchedGene = searchedGene.toLowerCase()
      filteredGenes = deGenes.filter(d => d.name.toLowerCase().includes(lowerCaseSearchedGene))
    }

    if (deGenes) {filteredGenes = filteredGenes.slice(0, numRows)}
    setGenesToShow(filteredGenes)
  }, [deGenes, searchedGene])

  return (
    <>
      <DifferentialExpressionGroupPicker
        bucketId={bucketId}
        clusterName={clusterName}
        annotation={annotation}
        setShowDeGroupPicker={setShowDeGroupPicker}
        deGenes={deGenes}
        setDeGenes={setDeGenes}
        deGroup={deGroup}
        setDeGroup={setDeGroup}
        countsByLabel={countsByLabel}
        deObjects={deObjects}
        setDeFilePath={setDeFilePath}
      />

      {genesToShow &&
      <>
        <div className="de-search-box">
          <span className="de-search-icon">
            <FontAwesomeIcon icon={faSearch} />
          </span>
          <input
            className="de-search-input no-border"
            name="de-search-input"
            type="text"
            autoComplete="off"
            placeholder="Find a gene" // Consensus per demo, to distinguish from main "Search genes" in same UI
            value={searchedGene}
            onChange={event => updateSearchedGene(event.target.value, 'keydown')}
            data-analytics-name="differential-expression-search"
          />
          { showClear && <Button
            type="button"
            data-analytics-name="clear-de-search"
            className="clear-de-search-icon"
            aria-label="Clear"
            onClick={handleClear} >
            <FontAwesomeIcon icon={faTimes} />
          </Button> }
        </div>

        <div className="de-table-buttons">
          <DownloadButton bucketId={bucketId} deFilePath={deFilePath} />
          <DifferentialExpressionModal />
        </div>

        <DifferentialExpressionTable
          genesToShow={genesToShow}
          searchGenes={searchGenes}
          checked={checked}
          clusterName={clusterName}
          annotation={annotation}
          species={species}
          changeRadio={changeRadio}
        />
      </>
      }
    </>
  )
}

/** Top matter for differential expression panel shown at right in Explore tab */
export function DifferentialExpressionPanelHeader({
  setDeGenes, setDeGroup, setShowDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel, isUpstream,
  cluster, annotation
}) {
  return (
    <>
      <span>Differential expression</span>
      <button className="action fa-lg"
        onClick={() => {
          setDeGenes(null)
          setDeGroup(null)
          setShowDifferentialExpressionPanel(false)
          setShowUpstreamDifferentialExpressionPanel(false)
        }}
        title="Exit differential expression panel"
        data-analytics-name="differential-expression-panel-exit">
        <FontAwesomeIcon icon={faArrowLeft}/>
      </button>
      {isUpstream &&
        <>
          <div className="de-nondefault-explainer">
          No DE results for:
            <br/><br/>
            <ul className="no-de-summary">
              <li>
                <span className="bold">Clustering</span><br/>
                {cluster}
              </li>
              <br/>
              <li>
                <span className="bold">Annotation</span><br/>
                {annotation.name}
              </li>
            </ul>
            <br/>
          Explore DE results in:
          </div>
        </>
      }
    </>
  )
}
