import React, { useContext, useEffect, useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'
import CreatableSelect from 'react-select/creatable'

import { GeneSearchContext, buildParamsFromQuery } from '~/providers/GeneSearchProvider'
import { StudySearchContext } from '~/providers/StudySearchProvider'
import { useLocation } from '@reach/router'

/** renders the gene text input
  * This is split into its own component both for modularity, and also because
  * having it inlined in GeneSearchView led to a mysterious infinite-repaint bug in StudyResults
  */
export default function GeneKeyword({ placeholder, helpTextContent }) {
  const location = useLocation()
  const geneSearchState = useContext(GeneSearchContext)
  const studySearchState = useContext(StudySearchContext)
  const searchedGenesAsArray = getGenesFromLocation()

  // use URL genes param for tracking state of gene search bar
  function getGenesFromLocation() {
    const searchParams = buildParamsFromQuery(location.search)
    if (searchParams.genes) {
      return searchParams.genes.split(' ').map(geneName => ({
        label: geneName,
        value: geneName
      }))
    } else {
      return []
    }
  }

  /** the search control tracks two state variables
    * an array of already entered genes (geneArray),
    * and the current text the user is typing (inputText) */
  const [geneArray, setGeneArray] = useState(searchedGenesAsArray)
  const [inputText, setInputText] = useState('')

  useEffect(() => {
    setGeneArray(searchedGenesAsArray)
  }, [searchedGenesAsArray.map(gene => {return gene.label}).join(' ')])

  /** handles a user submitting a gene search */
  function handleSubmit(event) {
    event.preventDefault()
    const newGeneArray = syncGeneArrayToInputText()
    if (newGeneArray && newGeneArray.length) {
      geneSearchState.updateSearch(
        // flatten the gene array back to a space-delimited string
        { genes: newGeneArray.map(g => g.value).join(' ') },
        studySearchState
      )
    } else {
      geneSearchState.updateSearch(
        { genes: '' },
        studySearchState
      )
    }
  }

  /** Converts any current typed free text to a gene array entry */
  function syncGeneArrayToInputText() {
    const inputTextTrimmed = inputText.trim().replace(/,/g, '')
    if (!inputTextTrimmed) {
      return geneArray
    }
    const newGeneArray = [...geneArray, { label: inputTextTrimmed, value: inputTextTrimmed }]

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

  return (
    <form className="gene-keyword-search form-horizontal" onSubmit={handleSubmit}>
      <div className="input-group">
        <CreatableSelect
          components={{ DropdownIndicator: null }}
          inputValue={inputText}
          value={geneArray}
          className="gene-keyword-search-input"
          isMulti
          isClearable
          menuIsOpen={false}
          onChange={value => setGeneArray(value ? value : [])}
          onInputChange={inputValue => setInputText(inputValue)}
          onKeyDown={handleKeyDown}
          // the default blur behavior removes any entered free text,
          // we want to instead auto-convert entered free text to a gene tag
          onBlur={syncGeneArrayToInputText}
          placeholder={placeholder}
        />
        <div className="input-group-append">
          <Button type="submit" aria-label="Search genes">
            <FontAwesomeIcon icon={faSearch} />
          </Button>
        </div>
      </div>
    </form>
  )
}
