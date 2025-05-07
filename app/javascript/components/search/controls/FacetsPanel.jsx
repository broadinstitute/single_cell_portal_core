import React, { useContext, useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faQuestionCircle } from '@fortawesome/free-solid-svg-icons'
import Modal from 'react-bootstrap/lib/Modal'

import { closeModal } from '~/components/search/controls/SearchPanel'
import FacetControl from './FacetControl'
import CombinedFacetControl from './CombinedFacetControl'
import MoreFacetsButton from './MoreFacetsButton'
import { SearchFacetContext } from '~/providers/SearchFacetProvider'

const defaultFacetIds = ['disease', 'species']
const moreFacetIds = [
  'sex', 'race', 'library_preparation_protocol', 'organism_age', 'has_morphology', 'has_electrophysiology'
]

/**
 * Container for horizontal list of facet buttons, and "More facets" button
 */
export default function FacetsPanel() {
  const searchFacetContext = useContext(SearchFacetContext)
  const defaultFacets = searchFacetContext.facets.filter(facet => defaultFacetIds.includes(facet.id))
  const moreFacets = searchFacetContext.facets.filter(facet => moreFacetIds.includes(facet.id))
  const [showSearchHelpModal, setShowSearchHelpModal] = useState(false)

  const publicStudies = window.SCP.studyStats.public
  const compliantStudies = window.SCP.studyStats.compliant
  const percentage = Math.round(compliantStudies / publicStudies * 100)
  const helpModalContent = (<div>
    <h4 className="text-center">Faceted search</h4><br/>
    Single Cell Portal supports searching on facets of studies by ontology classifications.  This lets users
    search for studies using metadata that may not appear in titles or descriptions.
    <br/><br/>
    For example, you can search on studies that
    have <b>species</b> of <b>&quot;Homo sapiens&quot;</b> or have an <b>organ</b> of <b>&quot;brain&quot;</b>.{' '}
    ~<b>{percentage}% ({compliantStudies} of {publicStudies})</b> public studies in SCP provide this metadata
    information.
    {/*
   more information on public/compliant studies available at
   https://docs.google.com/spreadsheets/d/1FSpP2XTrG9FqAqD9X-BHxkCZae9vxZA3cQLow8mn-bk
*/}
    <br/><br/>
    For more detailed information, visit
    our{' '}
    <a href="https://singlecell.zendesk.com/hc/en-us/articles/360061006431-Search-Studies"
      target="_blank" rel="noreferrer">documentation
    </a>.  Study authors looking to make their studies more accessible can read our
    <a href="https://singlecell.zendesk.com/hc/en-us/articles/4406379107355-Metadata-powered-Advanced-Search"
      target="_blank" rel="noreferrer"> metadata guide
    </a>.
  </div>)

  const advancedOptsLink = <a className="action advanced-opts"
    onClick={() => setShowSearchHelpModal(true)}
    data-analytics-name="search-help">
    <FontAwesomeIcon icon={faQuestionCircle} />
  </a>

  return (
    <div className='metadata-search-wrap'>
      <span
        className='metadata-search search-title'
      >
        Search by filters { advancedOptsLink }
      </span>
      <CombinedFacetControl controlDisplayName="organ" facetIds={['organ', 'organ_region']}/>
      {
        defaultFacets.map((facet, i) => {
          return <FacetControl facet={facet} key={i}/>
        })
      }
      <CombinedFacetControl controlDisplayName="cell type" facetIds={['cell_type', 'cell_type__custom']}/>
      <MoreFacetsButton facets={moreFacets} />
      <Modal
        show={showSearchHelpModal}
        onHide={() => closeModal(setShowSearchHelpModal)}
        animation={false}
        bsSize='large'>
        <Modal.Body className="">
          { helpModalContent }
        </Modal.Body>
      </Modal>
    </div>

  )
}
