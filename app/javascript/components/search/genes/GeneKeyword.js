import React, { useContext, useState, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faTimes, faSearch } from '@fortawesome/free-solid-svg-icons'
import _clone from 'lodash/clone'
import Button from 'react-bootstrap/lib/Button'
import Modal from 'react-bootstrap/lib/Modal'

import { GeneSearchContext } from 'providers/GeneSearchProvider'
import { StudySearchContext } from 'providers/StudySearchProvider'

/** renders the gene text input
  * This is split into its own component both for modularity, and also because
  * having it inlined in GeneSearchView led to a mysterious infinite-repaint bug in StudyResults
  * this shares a lot of UI/functionality with KeywordSearch.js, so it's a candidate for future refactoring
  */
export default function GeneKeyword({ placeholder }) {
  const geneSearchState = useContext(GeneSearchContext)
  const studySearchState = useContext(StudySearchContext)
  const [genes, setGenes] = useState(_clone(geneSearchState.params.genes))
  const [showEmptySearchModal, setShowEmptySearchModal] = useState(false)

  const showClear = genes && genes.length
  const inputField = useRef()

  /** handles a user submitting a gene search */
  function handleSubmit(event) {
    event.preventDefault()
    if (genes && genes.length) {
      geneSearchState.updateSearch({ genes }, studySearchState)
    } else {
      setShowEmptySearchModal(true)
    }
  }

  function handleClear() {
    inputField.current.focus()
    geneSearchState.updateSearch({ genes: '' }, studySearchState)
    setGenes('')
  }

  return (
    <form className="gene-keyword-search form-horizontal" onSubmit={handleSubmit}>
      <div className="input-group">
        <input type="text"
          ref={inputField}
          className="form-control"
          value={genes}
          size="50"
          onChange={e => setGenes(e.target.value)}
          placeholder={placeholder}
          name="genes-text-input"/>
        <div className="input-group-append">
          <Button type="submit">
            <FontAwesomeIcon icon={faSearch} />
          </Button>
        </div>
        { showClear &&
          <Button className="keyword-clear"
            type='button'
            onClick={handleClear} >
            <FontAwesomeIcon icon={faTimes} />
          </Button> }
      </div>
      <Modal
        show={showEmptySearchModal}
        onHide={() => {setShowEmptySearchModal(false)}}
        animation={false}
        bsSize='small'>
        <Modal.Body className="text-center">
          You must enter at least one gene to search
        </Modal.Body>
      </Modal>
    </form>
  )
}
