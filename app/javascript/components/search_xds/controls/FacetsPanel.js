import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSlidersH } from '@fortawesome/free-solid-svg-icons'

import FacetsAccordion from './FacetsAccordion'
import { StudySearchContext } from 'providers/StudySearchProvider'
import useCloseableModal from 'hooks/closeableModal'

/**
 * Component for "More Facets" button.  Clicking shows facets accordion box.
 *
 * UI spec: https://projects.invisionapp.com/d/main#/console/19272801/402387756/preview
 */
export default function FacetsPanel(props) {
  const searchContext = useContext(StudySearchContext)
  const [show, setShow] = useState(false)

  const { node, handleButtonClick } = useCloseableModal(show, setShow)

  const numFacetsApplied = props.facets.filter(facet => {
    const facets = searchContext.params.facets
    return facets[facet.id] && facets[facet.id].length
  }).length
  const facetCountString = numFacetsApplied > 0 ? `(${numFacetsApplied})` : ''

  console.log('props.facets', props.facets)

  return (
    <FacetsAccordion facets={props.facets} setShow={setShow} />
  )
}
