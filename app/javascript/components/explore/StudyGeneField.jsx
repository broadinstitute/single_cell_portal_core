import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSearch, faFileUpload } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'
import Modal from 'react-bootstrap/lib/Modal'
import CreatableSelect from 'react-select/creatable'
import _differenceBy from 'lodash/differenceBy'

import { getAutocompleteSuggestions } from '~/lib/search-utils'
import { log } from '~/lib/metrics-api'
import { logStudyGeneSearch } from '~/lib/search-metrics'


/** renders the gene text input
  * This shares a lot of logic with search/genes/GeneKeyword, but is kept as a separate component for
  * now, as the need for autocomplete raises additional complexity
  *
  * @param genes Array of genes currently inputted
  * @param searchGenes Function to call to execute the API search
  * @param allGenes String array of valid genes in the study
  * @param speciesList String array of species scientific names
  */
export default function StudyGeneField({ genes, searchGenes, allGenes, speciesList, isLoading=false }) {
  const [inputText, setInputText] = useState('')

  const rawSuggestions = getAutocompleteSuggestions(inputText, allGenes)
  const geneOptions = getOptionsFromGenes(rawSuggestions)

  let enteredGeneArray = []
  if (genes) {
    enteredGeneArray = getOptionsFromGenes(genes)
  }

  /** the search control tracks two state variables
    * an array of already entered genes (geneArray),
    * and the current text the user is typing (inputText) */
  const [geneArray, setGeneArray] = useState(enteredGeneArray)
  const [showEmptySearchModal, setShowEmptySearchModal] = useState(false)
  const [showTooManyGenesModal, setShowTooManyGenesModal] = useState(false)

  const [notPresentGenes, setNotPresentGenes] = useState(new Set([]))
  const [showNotPresentGeneChoice, setShowNotPresentGeneChoice] = useState(false)

  /** handles a user submitting a gene search */
  function handleSearch(event) {
    event.preventDefault()
    const newGeneArray = syncGeneArrayToInputText()
    const newNotPresentGenes = new Set([])
    if (newGeneArray) {
      newGeneArray.forEach(gene => {
        // if an entered gene is not in the valid gene options for the study
        const geneLowercase = gene.label.toLowerCase()
        if (allGenes.length > 0 && !allGenes.find(geneOpt => geneOpt.toLowerCase() === geneLowercase)) {
          newNotPresentGenes.add(gene.label)
        }
      })
    }
    setNotPresentGenes(newNotPresentGenes)
    if (newNotPresentGenes.size > 0) {
      setShowNotPresentGeneChoice(true)
    } else if (newGeneArray && newGeneArray.length) {
      const genesToSearch = newGeneArray.map(g => g.value)
      if (genesToSearch.length > window.MAX_GENE_SEARCH) {
        log('search-too-many-genes', {numGenes: genesToSearch.length})
        setShowTooManyGenesModal(true)
      } else {
        if (event) { // this was not a 'clear'
          const trigger = event.type // 'click' or 'submit'
          logStudyGeneSearch(genesToSearch, trigger, speciesList)
        }
        searchGenes(genesToSearch)
      }
    } else {
      setShowEmptySearchModal(true)
    }
  }

  /** Converts any current typed free text to a gene array entry */
  function syncGeneArrayToInputText() {
    const inputTextValues = inputText.trim().split(/[\s,]+/)
    if (!inputTextValues.length || !inputTextValues[0].length) {
      return geneArray
    }
    const newGeneArray = geneArray.concat(getOptionsFromGenes(inputTextValues))
    logGeneArrayChange(newGeneArray)
    setInputText(' ')
    setGeneArray(newGeneArray)
    return newGeneArray
  }

  /** detects presses of the space bar to create a new gene chunk */
  function handleKeyDown(event) {
    if (!inputText) {
      return
    }
    switch (event.key) {
      case ' ':
      case ',':
        syncGeneArrayToInputText()
        setTimeout(() => {setInputText(' ')}, 0)
    }
  }

  /** handles a user selecting a gene list file to use */
  function readGeneListFile(file) {
    const fileReader = new FileReader()
    fileReader.onloadend = () => {
      const newGenes = fileReader.result.trim().split(/[\s,]+/)
      searchGenes(newGenes)
    }
    fileReader.readAsText(file)
  }

  /** send analytics on how the gene search input changed */
  function logGeneArrayChange(newArray) {
    try {
      let actionName = ''
      let geneDiff = []
      if (newArray.length > geneArray.length) {
        actionName = 'add'
        geneDiff = _differenceBy(newArray, geneArray, 'value')
      } else {
        actionName = 'remove'
        geneDiff = _differenceBy(geneArray, newArray, 'value')
      }
      log('change:multiselect', {
        text: geneDiff.map(item => item.value).join(','),
        action: actionName,
        type: 'gene',
        numPreviousGenes: geneArray.length
      })
    } catch (err) {
      // no-op, we just don't want logging fails to break the application
    }
  }

  /** handles the change event corresponding a a user adding or clearing one or more genes */
  function handleSelectChange(value) {
    // react-select doesn't expose the actual click events, so we deduce the kind
    // of operation based on whether it lengthened or shortened the list
    const newValue = value ? value : []
    setNotPresentGenes(new Set([]))
    logGeneArrayChange(newValue)
    setGeneArray(newValue)
  }

  useEffect(() => {
    if (genes.join(',') !== geneArray.map(opt => opt.label).join(',')) {
      // the genes have been updated elsewhere -- resync
      setGeneArray(getOptionsFromGenes(genes))
      setInputText('')
      setNotPresentGenes(new Set([]))
    }
  }, [genes.join(',')])

  const searchDisabled = !isLoading && !allGenes?.length

  return (
    <form className="gene-keyword-search gene-study-keyword-search form-horizontal" onSubmit={handleSearch}>
      <div className="flexbox align-center">
        <div className="input-group">
          <div className="input-group-append">
            <Button type="button" data-analytics-name="gene-search-submit" onClick={handleSearch} disabled={searchDisabled}>
              <FontAwesomeIcon icon={faSearch} />
            </Button>
          </div>
          <CreatableSelect
            components={{ DropdownIndicator: null }}
            inputValue={inputText}
            value={geneArray}
            className={searchDisabled ? 'gene-keyword-search-input disabled' : 'gene-keyword-search-input'}
            isClearable
            isMulti
            isValidNewOption={() => false}
            noOptionsMessage={() => (inputText.length > 1 ? 'No matching genes' : 'Type to search...')}
            options={geneOptions}
            onChange={handleSelectChange}
            onInputChange={inputValue => setInputText(inputValue)}
            onKeyDown={handleKeyDown}
            // the default blur behavior removes any entered free text,
            // we want to instead auto-convert entered free text to a gene tag
            onBlur={syncGeneArrayToInputText}
            placeholder={searchDisabled ? 'No expression data to search' : 'Genes (e.g. "PTEN NF2")'}
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
        show={showEmptySearchModal}
        onHide={() => {setShowEmptySearchModal(false)}}
        animation={false}
        bsSize='small'>
        <Modal.Body className="text-center">
          Enter at least one gene to search
        </Modal.Body>
      </Modal>
      <Modal
        show={showNotPresentGeneChoice}
        onHide={() => {setShowNotPresentGeneChoice(false)}}
        animation={false}
        bsSize='small'>
        <Modal.Body className="text-center">
        Invalid Search - Please remove &quot;{Array.from(notPresentGenes).join('", "')}&quot; from gene search.
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

/** takes an array of gene name strings, and returns options suitable for react-select */
function getOptionsFromGenes(genes) {
  return genes.map(geneName => ({
    label: geneName,
    value: geneName
  }))
}
