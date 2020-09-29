import React, { useContext, useRef } from 'react'
import Button from 'react-bootstrap/lib/Button'
import InputGroup from 'react-bootstrap/lib/InputGroup'
import Form from 'react-bootstrap/lib/Form'
import { faSearch, faTimes } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { SearchSelectionContext } from 'providers/SearchSelectionProvider'

/**
 * Component to search using a keyword value
 * optionally takes a 'keywordValue' prop with the initial value for the field
 */
export default function KeywordSearch({ keywordPrompt }) {
  const placeholder = keywordPrompt ? keywordPrompt : 'Enter keyword'
  const selectionContext = useContext(SearchSelectionContext)
  // show clear button after a search has been done,
  //  as long as the text hasn't been updated
  const showClear = selectionContext.terms && selectionContext.terms.length
  const inputField = useRef()
  /**
   * Updates terms in search context upon submitting keyword search
   */
  function handleSubmit(event) {
    event.preventDefault()
    selectionContext.performSearch()
  }

  function handleKeywordChange(newValue) {
    selectionContext.updateSelection({ terms: newValue })
  }

  function handleClear() {
    inputField.current.focus()
    selectionContext.updateSelection({ terms: '' }, true)
  }

  return (
    <Form
      horizontal
      onSubmit = {handleSubmit}
      className='study-keyword-search'
    >
      <InputGroup>
        <input
          ref = {inputField}
          className="form-control"
          size="30"
          type="text"
          value={selectionContext.terms}
          onChange={e => handleKeywordChange(e.target.value)}
          placeholder={placeholder}
          name="keywordText"/>
        <div className="input-group-append">
          <Button type='submit'>
            <FontAwesomeIcon icon={faSearch} />
          </Button>
        </div>
        { showClear &&
          <Button className="keyword-clear"
            type='button'
            onClick={handleClear} >
            <FontAwesomeIcon icon={faTimes} />
          </Button> }
      </InputGroup>
    </Form>
  )
}
