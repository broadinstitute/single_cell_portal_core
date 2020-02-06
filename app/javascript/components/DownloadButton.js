import React, { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faArrowDown } from '@fortawesome/free-solid-svg-icons';
import BulkDownloadModal from './BulkDownloadModal';

/**
 * Component for "Download" button.  Clicking shows Bulk Download modal.
 *
 * UI spec: https://projects.invisionapp.com/d/main#/console/19272801/402387755/preview
 */
export default function DownloadButton(props) {

  const [show, setShow] = useState(false);

  function handleClick() {
    setShow(!show);
  }

  return (
      <span
        id='download-button'
        className={`${show ? 'active' : ''}`}>
        <span
          onClick={handleClick}>
          <FontAwesomeIcon className="icon-left" icon={faArrowDown}/>
          Download
        </span>
        <BulkDownloadModal show={show} />
      </span>
    );
}
