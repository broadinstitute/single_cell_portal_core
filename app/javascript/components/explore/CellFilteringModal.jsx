import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import React, { useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'
import { closeModal } from '~/components/search/controls/SearchPanel'

/** Show modal box with information on differential expression in SCP */
export default function CellFilteringModal() {
  const [showCellFacetModal, setShowCellFacetModall] = useState(false)
  const cellFacetModalContent = (
    <div>
      <p>
        Cell filtering lets you easily plot cells that match criteria <i>across annotations</i>.
      </p>
      <p>
        As a hypothetical example, cell filtering can let you quickly subset a plot to show only cells annotated as from lymphoma <i>and</i> males.
        You would click to update the filters so only "lymphoma" is checked in "Disease" and "male" is checked in "Sex".
      </p>
    </div>
  )

  const cellFacetModalHelpLink = (
    <a
      onClick={() => setShowCellFacetModall(true)}
      data-analytics-name="cell-filtering-info-help-icon"
      data-toggle="tooltip"
      data-original-title="Click to learn about cell filtering"
      className="cell-filtering-info-help-icon"
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
          <h4 className="text-center">Cell filtering</h4>
        </Modal.Header>
        <Modal.Body>
          { cellFacetModalContent }
        </Modal.Body>
      </Modal>
    </>
  )
}
