import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSearch, faFileUpload } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'
import Modal from 'react-bootstrap/lib/Modal'
import CreatableSelect from 'react-select/creatable'

import { getAutocompleteSuggestions, getIsPathway } from '~/lib/search-utils'
import { log } from '~/lib/metrics-api'
import { logStudyGeneSearch } from '~/lib/search-metrics'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import { manageDrawPathway } from '~/lib/pathway-expression'

/** Determine if searched text is among available genes */
function getIsInvalidQuery(query, allGenes) {
  const queryLowercase = query.toLowerCase()
  const isInvalidQuery = (
    allGenes.length > 0 &&
    !allGenes.find(geneOpt => geneOpt.toLowerCase() === queryLowercase) &&
    !getIsPathway(query)
  )
  return isInvalidQuery
}

/** Parse gene name from heterogeneous array  */
function getQueriesFromSearchOptions(newQueryArray) {
  let newQueries
  let isGene = true
  const flags = getFeatureFlagsWithDefaults()

  if (newQueryArray[0]?.isGene === true || !flags?.show_pathway_expression) {
    // Query is a gene
    console.log('in getQueriesFromSearchOptions, case 1')
    newQueries = newQueryArray.map(g => g.value)
  } else if (newQueryArray.length === 0) {
    // Query is empty
    console.log('in getQueriesFromSearchOptions, case 2')
    newQueries = []
  } else if (newQueryArray[0].isGene === false) {
    console.log('in getQueriesFromSearchOptions, case 3')
    // Query is a pathway
    newQueries = [newQueryArray[0].value]
  } else {
    console.log('in getQueriesFromSearchOptions, case 4')
    // Accounts for clearing genes
    newQueries = newQueryArray[0].options.map(g => g.value)
    isGene = false
  }

  console.log('in getQueriesFromSearchOptions, newQueries', newQueries)

  return newQueries
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
*/
export default function StudyGeneField({ queries, queryFn, allGenes, speciesList, isLoading=false }) {
  const [inputText, setInputText] = useState('')

  const rawSuggestions = getAutocompleteSuggestions(inputText, allGenes)
  const searchOptions = getSearchOptions(rawSuggestions)

  let enteredQueryArray = []
  if (queries) {
    enteredQueryArray = getSearchOptions(queries)
  }

  /** the search control tracks two state variables
    * an array of already entered queries (queryArray),
    * and the current text the user is typing (inputText) */
  const [queryArray, setQueryArray] = useState(enteredQueryArray)
  const [showTooManyGenesModal, setShowTooManyGenesModal] = useState(false)

  const [notPresentQueries, setNotPresentQueries] = useState(new Set([]))
  const [showNotPresentGeneChoice, setShowNotPresentGeneChoice] = useState(false)

  const flags = getFeatureFlagsWithDefaults()

  /** Handles a user submitting a gene search */
  function handleSearch(event) {
    event.preventDefault()
    const newQueryArray = syncQueryArrayToInputText()
    console.log('in handleSearch, newQueryArray', newQueryArray)

    const newNotPresentQueries = new Set([])
    if (newQueryArray) {
      if (!flags?.show_pathway_expression) {
        newQueryArray.map(g => g.value).forEach(query => {
          // if an entered gene is not in the valid gene options for the study
          const isInvalidQuery = getIsInvalidQuery(query, allGenes)
          if (isInvalidQuery) {
            newNotPresentQueries.add(query)
          }
        })
      } else {
        const newQueries = getQueriesFromSearchOptions(newQueryArray)
        console.log('in handleSearch, newQueries', newQueries)
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
      const newQueries = getQueriesFromSearchOptions(newQueryArray)
      console.log('in StudyGeneField, newQueries', newQueries)
      const queries = newQueries
      // console.log('in handleSearch, genesToSearch', genesToSearch)
      if (queries.length > window.MAX_GENE_SEARCH) {
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
      // console.log('in syncQueryArrayToInputText if, queryArray', queryArray)
      if (queryArray.length === 2 && queryArray[0].label === 'Genes') {
        return []
      } else {
        return queryArray
      }
    }
    const searchOptions = getSearchOptions(inputTextValues)
    const queryOptions = searchOptions[0].options
    // console.log('in syncQueryArrayToInputText, queryArray', queryArray)
    // console.log('in syncQueryArrayToInputText, queryOptions', queryOptions)
    const newQueryArray = queryArray.concat(queryOptions)
    setInputText(' ')
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
    console.log('in handleSelectChange, value', value)
    setNotPresentQueries(new Set([]))
    setQueryArray(newValue)
  }

  useEffect(() => {
    if (queries.join(',') !== queryArray.map(opt => opt.label).join(',')) {
      // the genes have been updated elsewhere -- resync
      // console.log('in useEffect, queryArray', queryArray)
      // console.log('in useEffect, genes', genes)
      setQueryArray(getSearchOptions(queries))
      setInputText('')
      setNotPresentQueries(new Set([]))
    }
  }, [queries.join(',')])


  useEffect(() => {
    if (
      queries.join(',') !== queryArray.map(opt => opt.label).join(',')
    ) {
      const selectEvent = new Event('change:multiselect')
      console.log('in useEffect, queryArray', queryArray)
      handleSearch(selectEvent)
    }
  }, [queryArray])

  const searchDisabled = !isLoading && !allGenes?.length

  let searchTermsArray = queryArray

  console.log('queries 2', queries)
  console.log('queryArray', queryArray)

  if (typeof queryArray[0] === 'object' && queryArray[1]?.options.length > 0) {
    const rawPathwayLabel = queryArray[1].options[0].label
    searchTermsArray = [queryArray[1].options[0].label]
  }

  console.log('searchTermsArray', searchTermsArray)

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
            value={searchTermsArray}
            className={searchDisabled ? 'gene-keyword-search-input disabled' : 'gene-keyword-search-input'}
            isClearable
            isMulti
            isValidNewOption={() => false}
            noOptionsMessage={() => (inputText.length > 1 ? 'No matching genes' : 'Type to search...')}
            options={searchOptions}
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
        {!searchDisabled && <label htmlFor="gene-list-upload"
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
function getSearchOptions(rawSuggestions) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.show_pathway_expression) {
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

    console.log('rawGeneOptions', rawGeneOptions)
    console.log('rawPathwayOptions', rawPathwayOptions)

    const [geneOptions, pathwayOptions] =
      filterSearchOptions(rawGeneOptions, rawPathwayOptions)

    const searchOptions = [
      { 'label': 'Genes', 'options': geneOptions },
      { 'label': 'Pathways', 'options': pathwayOptions }
    ]

    return searchOptions
  }
}
