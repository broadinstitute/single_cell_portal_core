import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import React, { useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'
import { closeModal } from '~/components/search/controls/SearchPanel'

/** Show modal box with information on differential expression in SCP */
export default function DifferentialExpressionModal() {
  const [showDeModal, setShowDeModal] = useState(false)
  const deModalContent = (
    <div>
      <p>These are exploratory results calculated automatically by SCP, not the study owner. Any discrepancies between
        these results and an associated publication may be because it benefits from methods different from SCP's.
        These results are intended purely as an aid in exploring this dataset.&nbsp;
      <a href="https://singlecell.zendesk.com/hc/en-us/articles/6059411840027"
        target="_blank" data-analytics-name="differential-expression-docs">
          Learn more
      </a> about how these results are computed.</p>
    </div>
  )

  const deModalHelpLink = (
    <a
      onClick={() => setShowDeModal(true)}
      data-analytics-name="differential-expression-info"
      data-toggle="tooltip"
      data-original-title="Click to learn about differential expression in SCP"
      className="de-info-help-icon"
    >
      <FontAwesomeIcon className="action help-icon" icon={faInfoCircle} />
    </a>
  )

  return (
    <>
      { deModalHelpLink }
      <Modal
        id="de-info-modal"
        show={showDeModal}
        onHide={() => closeModal(setShowDeModal)}
        animation={false}>
        <Modal.Header>
          <h4 className="text-center">Exploratory differential expression</h4>
        </Modal.Header>
        <Modal.Body>
          { deModalContent }
        </Modal.Body>
      </Modal>
    </>
  )
}
