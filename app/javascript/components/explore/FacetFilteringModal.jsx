import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import React, { useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'
import { closeModal } from '~/components/search/controls/SearchPanel'

/** Show modal box with information on differential expression in SCP */
export default function FacetFilteringModal() {
  const [showCellFacetModal, setShowCellFacetModall] = useState(false)
  const cellFacetModalContent = (
    <div>
      <p> Cell filtering provides the ability to view cell annotations within the context of other annotations.
        You can visualize the expression of particular cells in a subset of the dataset through the facet filters.
      </p>
      <p>
        For example - You might be interested in the diseased cells of a dataset, but only in the males of the dataset. You can
        choose any annotation to color your plot by and then chose facets Disease and Sex then filter for only diseased and male
        cells utilizing the check boxes to filter.
      </p>
    </div>
  )

  const cellFacetModalHelpLink = (
    <a
      onClick={() => setShowCellFacetModall(true)}
      data-analytics-name="cell-facet-filter-info"
      data-toggle="tooltip"
      data-original-title="Click to learn about cell facet filtering in SCP"
      className="cff-icon-style"
    >
      <FontAwesomeIcon className="action help-icon" icon={faInfoCircle} />
    </a>
  )

  return (
    <>
      { cellFacetModalHelpLink }
      <Modal
        id="de-info-modal"
        show={showCellFacetModal}
        onHide={() => closeModal(setShowCellFacetModall)}
        animation={false}>
        <Modal.Header>
          <h4 className="text-center">Cell Facet Filtering</h4>
        </Modal.Header>
        <Modal.Body>
          { cellFacetModalContent }
        </Modal.Body>
      </Modal>
    </>
  )
}
