
import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faSearch, faTimes, faAngleUp, faAngleDown, faUndo, faBullseye
} from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'

import DifferentialExpressionFilters from './DifferentialExpressionFilters'

import {
  OneVsRestDifferentialExpressionGroupPicker, PairwiseDifferentialExpressionGroupPicker
} from '~/components/visualization/controls/DifferentialExpressionGroupPicker'

import {
  logDifferentialExpressionTableSearch
} from '~/lib/search-metrics'

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

/** Top matter for differential expression panel shown at right in Explore tab */
export function CellFacetFilterPanel({
  setDeGenes, setDeGroup, setShowDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel, isUpstream,
  cluster, annotation, setDeGroupB, isAuthorDe, deGenes
}) {
  return (
    <>
      <button className="action fa-lg de-exit-panel"
        onClick={() => {
          setDeGenes(null)
          setDeGroup(null)
          setDeGroupB(null)
          setShowDifferentialExpressionPanel(false)
          setShowUpstreamDifferentialExpressionPanel(false)
        }}
        title="Exit facet filter panel"
        data-analytics-name="facet-filter-panel-exit">
        <FontAwesomeIcon icon={faArrowLeft}/>
      </button>
    </>
  )
}

/** Apply range filters to DE genes */
function rangeFilterGenes(deFacets, deGenes, activeFacets) {
  if (!deGenes || !Object.values(deFacets).some(filters => filters.length > 0)) {
    return deGenes
  }

  const facetEntries = Object.entries(deFacets)
  const filteredGenes = deGenes.filter(deGene => {
    let isMatch = true
    facetEntries.forEach(([facetName, filters]) => {
      if (
        filters.length === 0 ||
        activeFacets[facetName] === false
      ) {
        return
      }
      let satisfiesFilters = false
      const metricValue = deGene[facetName]
      filters.forEach(range => {
        if (metricValue >= range.min && metricValue <= range.max) {
          satisfiesFilters = true
        }
      })
      if (!satisfiesFilters) {isMatch = false}
    })
    return isMatch
  })

  return filteredGenes
}

/** Splits "FOO,BAR", "FOO BAR", or "FOO, BAR" into array */
function splitSearchedGenesString(searchedGenes) {
  if (Array.isArray(searchedGenes)) {return searchedGenes}
  if (searchedGenes === '') {return []}
  return searchedGenes.split(/[ ,]+/)
    .filter(text => text !== '')
}

/** Return hits for substring text search on DE gene names */
function searchGeneNames(searchedGenes, deGenes, findMode) {
  let texts = [searchedGenes]

  if (searchedGenes === '') {
    return [deGenes, texts]
  }

  texts = splitSearchedGenesString(searchedGenes)

  const lowerCaseTexts = texts.map(text => text.toLowerCase())

  const filteredGenes = deGenes.filter(deGene => {
    const lcGeneName = deGene.name.toLowerCase()
    return lowerCaseTexts.some(lcText => {
      if (findMode === 'full') {
        return lcGeneName === lcText
      } else {
        return lcGeneName.includes(lcText)
      }
    })
  })

  return [filteredGenes, texts]
}

/** Apply "Find a gene" and range slider facets to DE genes, return matches */
function filterGenes(searchedGenes, deGenes, deFacets, activeFacets, findMode) {
  let unfoundNames = []
  if (!deGenes) {return [deGenes, unfoundNames]}

  let [filteredGenes, texts] =
    searchGeneNames(searchedGenes, deGenes, findMode)
  filteredGenes = rangeFilterGenes(deFacets, filteredGenes, activeFacets)

  unfoundNames = texts.filter(
    text => !filteredGenes.some(gene => {
      const lcGeneName = gene.name.toLowerCase()
      const lcText = text.toLowerCase()
      if (findMode === 'full') {
        return lcGeneName === lcText
      } else {
        return lcGeneName.includes(lcText)
      }
    })
  ).filter(name => name !== '')
  return [filteredGenes, unfoundNames]
}

/** Clear tooltips, i.e. close / remove any open small black tooltips */
function clearTooltips() {
  document.querySelectorAll('.tooltip.fade.top.in').forEach(e => e.remove())
}

/** Differential expression panel shown at right in Explore tab */
export default function DifferentialExpressionPanel({
  deGroup, deGenes, searchGenes,
  exploreInfo, exploreParamsWithDefaults, setShowDeGroupPicker, setDeGenes, setDeGroup,
  countsByLabel, hasOneVsRestDe, hasPairwiseDe, isAuthorDe, deGroupB, setDeGroupB, numRows=50
}) {
  const clusterName = exploreParamsWithDefaults?.cluster
  const bucketId = exploreInfo?.bucketId
  const annotation = getAnnotationObject(exploreParamsWithDefaults, exploreInfo)
  const deObjects = exploreInfo?.differentialExpression

  const delayedDETableLogTimeout = useRef(null)

  const defaultDeFacets = {
    'log2FoldChange': [{ min: -Infinity, max: 0.26 }, { min: 0.26, max: Infinity }]
  }
  const fdrMetric = !isAuthorDe ? 'pvalAdj' : 'qval'
  defaultDeFacets[fdrMetric] = [{ min: 0, max: 0.05 }]
  const defaultActiveFacets = { 'log2FoldChange': true }
  defaultActiveFacets[fdrMetric] = true
  const [deFacets, setDeFacets] = useState(defaultDeFacets)
  const [activeFacets, setActiveFacets] = useState(defaultActiveFacets)

  // Whether to match on full string or partial string for each token in "Find genes"
  const [findMode, setFindMode] = useState('partial')

  const filteredDeGenes = rangeFilterGenes(deFacets, deGenes, activeFacets)

  // filter text for searching the legend
  const [genesToShow, setGenesToShow] = useState(filteredDeGenes)
  const [searchedGenes, setSearchedGenes] = useState('')
  const [unfoundGenes, setUnfoundGenes] = useState([])

  const [deFilePath, setDeFilePath] = useState(null)

  const species = exploreInfo?.taxonNames

  /** Change filter values for range slider facets */
  function updateDeFacets(newFacets, metric) {
    setDeFacets(newFacets)
    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, newFacets, activeFacets, findMode)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)

    const otherProps = { trigger: 'update-facet', facet: metric }

    const searchedGenesArray = splitSearchedGenesString(searchedGenes)
    logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
  }

  /** Enable or disable slider range facet; preserve filter in background */
  function toggleDeFacet(metric) {
    const newActiveFacets = Object.assign(activeFacets, {})
    newActiveFacets[metric] = !newActiveFacets[metric]

    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, deFacets, newActiveFacets, findMode)

    setActiveFacets(newActiveFacets)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)

    const otherProps = { trigger: 'toggle-facet', facet: metric }
    const searchedGenesArray = splitSearchedGenesString(searchedGenes)
    logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
  }

  /** Handle a user pressing the 'x' to clear the 'Find a gene' field */
  function handleClear() {
    updateSearchedGenes('', 'clear')

    // Clicking 'x' doesn't clear facets, so apply any active facets
    const [filteredGenes, unfoundNames] = filterGenes('', deGenes, deFacets, activeFacets, findMode)

    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)
  }

  /** Switch match mode for "Find genes" */
  function handleFindModeToggle() {
    const newFindMode = findMode === 'partial' ? 'full' : 'partial'
    setFindMode(newFindMode)
    clearTooltips()
  }

  /** Only show clear button if text is entered in search box */
  const showClear = searchedGenes !== ''

  /** Set searched gene, and log search after 1 second delay */
  function updateSearchedGenes(newSearchedGenes, trigger) {
    newSearchedGenes =
      newSearchedGenes
        .replace(/\r?\n/g, ' ') // Replace newlines (Unix- or Windows-style) with spaces
        .replace(/\t/g, ' ')

    setSearchedGenes(newSearchedGenes)

    // Log search on DE table after 1 second since last change
    // This prevents logging "searches" on "P", "T", "E", and "N" if
    // the string "PTEN" is typed in a speed plausible for someone who
    // knows they want to search PTEN, without stopping to explore interstitial
    // results in the DE table.
    clearTimeout(delayedDETableLogTimeout.current)
    delayedDETableLogTimeout.current = setTimeout(() => {
      const otherProps = { trigger }
      const genes = [newSearchedGenes]
      const searchedGenesArray = splitSearchedGenesString(newSearchedGenes)
      logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
    }, 1000)
  }

  /** Update genes in table based on what user searches, filters */
  useEffect(() => {
    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, deFacets, activeFacets, findMode)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)
  }, [deGenes, searchedGenes, findMode])

  return (
    <>
      {!hasPairwiseDe &&
        <OneVsRestDifferentialExpressionGroupPicker
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
          isAuthorDe={isAuthorDe}
        />
      }
      {hasPairwiseDe &&
        <PairwiseDifferentialExpressionGroupPicker
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
          deGroupB={deGroupB}
          setDeGroupB={setDeGroupB}
          hasOneVsRestDe={hasOneVsRestDe}
        />
      }

      {
        (
          (!hasPairwiseDe && genesToShow) ||
          (hasPairwiseDe && deGroupB && genesToShow)
        ) &&
      <>
        <DifferentialExpressionFilters
          deFacets={deFacets}
          activeFacets={activeFacets}
          updateDeFacets={updateDeFacets}
          toggleDeFacet={toggleDeFacet}
          isAuthorDe={isAuthorDe}
        />
        <div className="de-search-box">
          <span className="de-search-icon">
            <FontAwesomeIcon icon={faSearch} />
          </span>
          <input
            className="de-search-input no-border"
            name="de-search-input"
            type="text"
            autoComplete="off"
            placeholder="Find genes" // Distinguishing from main "Search genes" in same UI
            value={searchedGenes}
            onChange={event => updateSearchedGenes(event.target.value, 'keydown')}
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
        {searchedGenes.length > 0 &&
          <a
            data-analytics-name="de-find-mode"
            className={`de-find-mode-icon ${findMode}`}
            data-toggle="tooltip"
            data-original-title={
              `Matching ${findMode} names.  Click for ${findMode === 'partial' ? 'only full' : 'partial'} matches.`
            }
            onClick={handleFindModeToggle} >
            <FontAwesomeIcon icon={faBullseye} />
          </a>
        }
      </>
      }
    </>
  )
}
