import React, { useState } from 'react';
import Modal from 'react-bootstrap/lib/Modal';
import Button from 'react-bootstrap/lib/Button';

export default function BulkDownloadModel(props) {
  // const [show, setShow] = useState(true);

  const handleClose = () => {} //setShow(false);
  const handleShow = () => {} //setShow(true);

  console.log('props')
  console.log(props)

  return(
    <>
      <div>test</div>
      <Modal id='bulk-download-modal' show={props.show} className={props.show ? 'in' : ''} onHide={handleClose} animation='false'>
        <Modal.Header closeButton>
          <Modal.Title>Bulk Download</Modal.Title>
        </Modal.Header>

        <Modal.Body>
          <p className='lead'>To download all files using <code>curl</code>, click the button below to get the download command:</p>
          <p className='lead command-container' id='command-container-all'>
            <Button
              className='fas fa-download'
              id='get-download-command_all'
            />
          </p>
        </Modal.Body>

        <Modal.Footer>
          <Button variant='secondary' onClick={handleClose}>Close</Button>
          <Button variant='primary' onClick={handleClose}>Save changes</Button>
        </Modal.Footer>
      </Modal>
    </>
  );
}
