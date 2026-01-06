import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSearch, faFileUpload } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'
import Modal from 'react-bootstrap/lib/Modal'
import CreatableSelect from 'react-select/creatable'

import {
  getAutocompleteSuggestions, getIsPathway, getIsInPathwayTitle,
  getPathwayName, getPathwaysContainingGene
} from '~/lib/search-utils'
import { log } from '~/lib/metrics-api'
import { logStudyGeneSearch } from '~/lib/search-metrics'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

/** Determine if searched text is among available genes */
export function getIsInvalidQuery(query, allGenes) {
  const queryLowercase = query.toLowerCase()
  const isInvalidQuery = (
    allGenes.length > 0 &&
    !allGenes.find(geneOpt => geneOpt.toLowerCase() === queryLowercase) &&
    !getIsInPathwayTitle(query) &&
    !getPathwaysContainingGene(query).length > 0
  )
  return isInvalidQuery
}

/** Determine if text matches incomplete part of any pathway title  */
function getIsPartialPathwayMatch(query, allGenes) {
  const queryLowercase = query.toLowerCase()
  const isPartialPathwayMatch = (
    // If it's not a gene match
    allGenes.length > 0 &&
    !allGenes.find(geneOpt => geneOpt.toLowerCase() === queryLowercase) &&

    // And if it's _not_ a _complete_ pathway title but, but _is_ an _partial_ match
    !getIsPathway(query) &&
    getIsInPathwayTitle(query)
  )
  return isPartialPathwayMatch
}

/** Parse gene name from heterogeneous array  */
function getQueriesFromSearchOptions(newQueryArray, speciesList, selectedAnnotation) {
  let newQueries
  if (newQueryArray[0]?.isGene === true || !getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)) {
    // Query is a gene
    newQueries = newQueryArray.map(g => g.value)
  } else if (newQueryArray.length === 0) {
    // Query is empty
    newQueries = []
  } else if (newQueryArray[0].isGene === false) {
    // Query is a pathway
    newQueries = [newQueryArray[0].value]
  } else if (typeof newQueryArray[0] === 'object') {
    // Accounts for clearing genes
    newQueries = newQueryArray.map(g => g.value)
  } else {
    // Query is a gene, passed via URL
    newQueries = newQueryArray
  }

  return newQueries
}

/** Indicate whether pathway view should be available for this study */
export function getIsEligibleForPathwayExplore(speciesList, selectedAnnotation) {
  const isEligibleForPathwayExplore = (
    speciesList.length === 1 && speciesList[0] === 'Homo sapiens' &&
    selectedAnnotation.type === 'group' &&
    getFeatureFlagsWithDefaults()?.show_pathway_expression
  )
  return isEligibleForPathwayExplore
}

/** Collapse search options to query array */
function getQueryArrayFromSearchOptions(searchOptions, speciesList, selectedAnnotation) {
  let queryArray = []

  if (!getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)) {
    return searchOptions
  }

  searchOptions.map(optionsObj => {
    const labels = optionsObj.options
    queryArray = queryArray.concat(labels)
  })

  return queryArray
}

/**
* Renders the gene text input
* This shares a lot of logic with search/genes/GeneKeyword, but is kept as a separate component for
* now, as the need for autocomplete raises additional complexity
*
* @param queries Array of genes or pathway currently inputted
* @param queryFn Function to call to execute the API search
* @param allGenes String array of valid genes in the study
* @param speciesList String array of species scientific names
* @param isLoading boolean flag for disabling search while loading
* @param disableGeneQueryLimit boolean flag for allowing searches larger than 50 genes for preprocessed data
*/
export default function StudyGeneField({
  queries, queryFn, allGenes, speciesList, selectedAnnotation, isLoading=false, disableGeneQueryLimit = false
}) {
  const [inputText, setInputText] = useState('')

  const includePathways = getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)
  const rawSuggestions = getAutocompleteSuggestions(inputText, allGenes, includePathways)
  const searchOptions = getSearchOptions(rawSuggestions, speciesList, selectedAnnotation)

  let enteredQueryArray = []
  if (inputText.length === 0 && queries && queries.length > 0) {
    const queriesSearchOptions = getSearchOptions(queries, speciesList, selectedAnnotation)
    enteredQueryArray = getQueryArrayFromSearchOptions(queriesSearchOptions, speciesList, selectedAnnotation)
  } else {
    enteredQueryArray = searchOptions
  }

  /** the search control tracks two state variables
    * an array of already entered queries (queryArray),
    * and the current text the user is typing (inputText) */
  const [queryArray, setQueryArray] = useState(enteredQueryArray)
  const [showTooManyGenesModal, setShowTooManyGenesModal] = useState(false)

  const [notPresentQueries, setNotPresentQueries] = useState(new Set([]))
  const [showNotPresentGeneChoice, setShowNotPresentGeneChoice] = useState(false)

  /** Handles a user submitting a gene search */
  function handleSearch(event) {
    event.preventDefault()
    const newQueryArray = syncQueryArrayToInputText()

    const newNotPresentQueries = new Set([])
    if (newQueryArray) {
      if (!getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)) {
        newQueryArray.map(g => g.value).forEach(query => {
          // if an entered gene is not in the valid gene options for the study
          const isInvalidQuery = getIsInvalidQuery(query, allGenes)
          if (isInvalidQuery) {
            newNotPresentQueries.add(query)
          }
        })
      } else {
        const newQueries = getQueriesFromSearchOptions(newQueryArray, speciesList, selectedAnnotation)
        newQueries.forEach(query => {
          // if an entered gene is not in the valid gene options for the study
          const isInvalidQuery = getIsInvalidQuery(query, allGenes)
          if (isInvalidQuery) {
            newNotPresentQueries.add(query)
          }
        })
      }
    }
    setNotPresentQueries(newNotPresentQueries)

    if (newNotPresentQueries.size > 0) {
      setShowNotPresentGeneChoice(true)
    } else if (newQueryArray && newQueryArray.length) {
      const newQueries = getQueriesFromSearchOptions(newQueryArray, speciesList, selectedAnnotation)
      const queries = newQueries
      if (queries.length > window.MAX_GENE_SEARCH && !disableGeneQueryLimit) {
        log('search-too-many-genes', { numGenes: queries.length })
        setShowTooManyGenesModal(true)
      } else {
        if (event) { // this was not a 'clear'
          const trigger = event.type // 'click' or 'submit'
          logStudyGeneSearch(queries, trigger, speciesList)
        }
        queryFn(queries)
      }
    }
  }

  /** Converts any current typed free text to a gene array entry */
  function syncQueryArrayToInputText() {
    const inputTextValues = inputText.trim().split(/[\s,]+/)
    if (!inputTextValues.length || !inputTextValues[0].length) {
      if (queryArray.length === 2 && queryArray[0].label === 'Genes') {
        return []
      } else {
        return queryArray
      }
    }
    const searchOptions = getSearchOptions(inputTextValues, speciesList, selectedAnnotation)

    let queryOptions
    if (getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)) {
      queryOptions = searchOptions[0].options
    } else {
      queryOptions = searchOptions
    }

    const newQueryArray = queryArray.concat(queryOptions)
    setInputText('')
    setQueryArray(newQueryArray)
    return newQueryArray
  }

  /** Detects presses of the space bar to create a new gene chunk */
  function handleKeyDown(event) {
    if (!inputText) {
      return
    }
    switch (event.key) {
      case ' ':
        if (!getIsPartialPathwayMatch(inputText, allGenes)) {
          syncQueryArrayToInputText()
          setTimeout(() => {setInputText(' ')}, 0)
        }
        break
      case ',':
        syncQueryArrayToInputText()
        setTimeout(() => {setInputText(' ')}, 0)
    }
  }

  /** Handles a user selecting a gene list file to use */
  function readGeneListFile(file) {
    const fileReader = new FileReader()
    fileReader.onloadend = () => {
      const newQueries = fileReader.result.trim().split(/[\s,]+/)
      queryFn(newQueries)
    }
    fileReader.readAsText(file)
  }

  /** Handles the change event corresponding a user adding or clearing one or more genes */
  function handleSelectChange(value) {
    // react-select doesn't expose the actual click events, so we deduce the kind
    // of operation based on whether it lengthened or shortened the list
    const newValue = value ? value : []
    setNotPresentQueries(new Set([]))
    setQueryArray(newValue)
  }

  useEffect(() => {
    if (queries.join(',') !== queryArray.map(opt => opt.value).join(',')) {
      // the genes have been updated elsewhere -- resync
      const queriesSearchOptions = getSearchOptions(queries, speciesList, selectedAnnotation)
      const newQueryArray = getQueryArrayFromSearchOptions(queriesSearchOptions, speciesList, selectedAnnotation)
      setQueryArray(newQueryArray)
      setInputText('')
      setNotPresentQueries(new Set([]))
    }
  }, [queries.join(',')])


  useEffect(() => {
    if (
      queries.join(',') !== queryArray.map(opt => opt.label).join(',')
    ) {
      const selectEvent = new Event('change:multiselect')
      handleSearch(selectEvent)
    }
  }, [queryArray.join(',')])

  const searchDisabled = !isLoading && !allGenes?.length

  let isPathway = false
  if (typeof queryArray[0] === 'object' && getIsPathway(queryArray[0].label)) {
    isPathway = true
    const pathwayObj = queryArray[0]
    if (pathwayObj.value === pathwayObj.label) {
      pathwayObj.label = getPathwayName(pathwayObj.label)
    }
    queryArray[0] = pathwayObj
  } else if (typeof queryArray[0] === 'string' && getIsPathway(queryArray[0])) {
    // Seen when e.g. clicking pathway-type node in pathway diagram
    isPathway = true
    const pathwayId = queryArray[0]
    const pathwayObj = { label: getPathwayName(pathwayId), value: pathwayId }
    queryArray[0] = pathwayObj
  }

  return (
    <form className="gene-keyword-search gene-study-keyword-search form-horizontal" onSubmit={handleSearch}>
      <div className="flexbox align-center">
        <div className="input-group">
          <div className="input-group-append">
            <Button
              type="button"
              aria-label="Search genes"
              aria-disabled={searchDisabled}
              data-analytics-name="gene-search-submit"
              onClick={handleSearch}
              disabled={searchDisabled}>
              <FontAwesomeIcon icon={faSearch} />
            </Button>
          </div>
          <CreatableSelect
            components={{ DropdownIndicator: null }}
            inputValue={inputText}
            value={queryArray}
            className={searchDisabled ? 'gene-keyword-search-input disabled' : 'gene-keyword-search-input'}
            isClearable
            isMulti
            isValidNewOption={() => false}
            noOptionsMessage={() => (inputText.length > 1 ? 'No matching genes' : 'Type to search...')}
            options={searchOptions}
            filterOption={finalFilterOptions}
            onChange={handleSelectChange}
            onInputChange={inputValue => setInputText(inputValue)}
            onKeyDown={handleKeyDown}
            // the default blur behavior removes any entered free text,
            // we want to instead auto-convert entered free text to a gene tag
            onBlur={syncQueryArrayToInputText}
            placeholder={searchDisabled ? 'No expression data to search' : 'Search gene(s) and find plots'}
            isDisabled={searchDisabled}
            styles={{
              // if more genes are entered than fit, use a vertical scrollbar
              // this is probably not optimal UX, but good enough for first release and monitoring
              valueContainer: (provided, state) => ({
                ...provided,
                maxHeight: '32px',
                overflow: 'auto'
              }),
              menuList: (provided, state) => ({
                ...provided,
                zIndex: 999,
                background: '#fff'
              })
            }}
          />
        </div>
        {!searchDisabled && !isPathway && <label htmlFor="gene-list-upload"
          data-toggle="tooltip"
          className="icon-button"
          title="Upload a list of genes to search from a file">
          <input id="gene-list-upload" type="file" onChange={e => readGeneListFile(e.target.files[0])}/>
          <FontAwesomeIcon className="action fa-lg" icon={faFileUpload} />
        </label>}
      </div>
      <Modal
        show={showNotPresentGeneChoice}
        onHide={() => {setShowNotPresentGeneChoice(false)}}
        animation={false}
        bsSize='small'>
        <Modal.Body className="text-center">
          <p>
            Invalid search. &quot;{Array.from(notPresentQueries).join('", "')}&quot;
            is not a gene that was assayed in this study.
          </p>
          <p>
            Please remove &quot;{Array.from(notPresentQueries).join('", "')}&quot; from gene search.
          </p>
          <p>
            Hint: Start typing or hit space in the search bar to see suggestions of genes present in the study.
          </p>
        </Modal.Body>
      </Modal>
      <Modal
        show={showTooManyGenesModal}
        onHide={() => {setShowTooManyGenesModal(false)}}
        animation={false}
        bsSize='small'>
        <Modal.Body className="text-center">
          {window.MAX_GENE_SEARCH_MSG}
        </Modal.Body>
      </Modal>
    </form>
  )
}

/** Last filtering applied before showing selectable autocomplete options */
export function finalFilterOptions(option, rawInput) {
  const input = rawInput.toLowerCase()
  const label = 'label' in option ? option.label?.toLowerCase() : option.toLowerCase()
  const isPathway = option.data.isGene === false
  return isPathway || label.includes(input) // partial match
}

/** Ensure at least some matched pathways are glanceable */
function filterSearchOptions(rawGeneOptions, rawPathwayOptions) {
  const maxGenes = 4
  const numGenes = rawGeneOptions.length
  const numPathways = rawPathwayOptions.length

  if (numPathways === 0) {
    return [rawGeneOptions, rawPathwayOptions]
  } else if (numGenes > maxGenes) {
    const filteredGeneOptions = rawGeneOptions.slice(0, maxGenes)
    return [filteredGeneOptions, rawPathwayOptions]
  } else {
    return [rawGeneOptions, rawPathwayOptions]
  }
}

/** takes an array of gene name strings, and returns options suitable for react-select */
function getSearchOptions(rawSuggestions, speciesList, selectedAnnotation) {
  if (!getIsEligibleForPathwayExplore(speciesList, selectedAnnotation)) {
    return rawSuggestions.map(rawSuggestion => {
      const geneName = rawSuggestion
      return { label: geneName, value: geneName, isGene: true }
    })
  } else {
    const rawGeneOptions = []
    const rawPathwayOptions = []
    rawSuggestions.forEach(rawSuggestion => {
      if (typeof rawSuggestion === 'string' && !getIsPathway(rawSuggestion)) {
        const geneName = rawSuggestion
        rawGeneOptions.push({ label: geneName, value: geneName, isGene: true })
      } else {
        // This is a pathway suggestion, {label: pathway name, value: pathway ID}
        rawPathwayOptions.push(rawSuggestion)
      }
    })

    const [geneOptions, pathwayOptions] =
      filterSearchOptions(rawGeneOptions, rawPathwayOptions)

    const searchOptions = [
      { 'label': 'Genes', 'options': geneOptions },
      { 'label': 'Pathways', 'options': pathwayOptions }
    ]

    return searchOptions
  }
}
