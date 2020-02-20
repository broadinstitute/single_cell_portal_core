import React, { useState, useEffect } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faDownload } from '@fortawesome/free-solid-svg-icons';
import Modal from 'react-bootstrap/lib/Modal';
import Clipboard from 'react-clipboard.js';

import { fetchAuthCode } from 'lib/scp-api';

/**
 * Fetch auth code, build download command, return configuration object
 *
 * @returns {Object} Object for auth code, time interval, and download command
 */
async function generateDownloadConfig() {
  const searchQuery = '&file_types=metadata,expression&accessions=SCP1,SCP2';

  const {authCode, timeInterval} = await fetchAuthCode();

  const queryString = `?auth_code=${authCode}${searchQuery}`;

  // Gets a curl configuration ("cfg.txt") containing signed
  // URLs and output names for all files in the download object.
  const url = `${window.origin}/api/v1/bulk_download${queryString}`;
  const curlSecureFlag = (window.location.host === 'localhost') ? 'k' : ''; // "-k" === "--insecure"

  // This is what the user will run in their terminal to download the data.
  // To consider: check the node environment (either at compile or runtime) instead of the hostname
  const downloadCommand = (
    'curl "' + url + '" -' + curlSecureFlag + 'o cfg.txt; ' +
    'curl -K cfg.txt; rm cfg.txt'
  );

  return {
    authCode: authCode,
    timeInterval: timeInterval,
    downloadCommand: downloadCommand
  };
}

function DownloadCommandContainer() {

  const [downloadConfig, setDownloadConfig] = useState({});

  useEffect(() => {
    const fetchData = async () => {
      const dlConfig = await generateDownloadConfig();
      setDownloadConfig(dlConfig);
    };
    fetchData();
  }, []);

  function onSuccess() {
    console.log('TODO (SCP-2121): Show "Copied!" tooltip');
  }

  return (
    <div>
      <div className='input-group'>
        <input
          id={'command-' + downloadConfig.authCode}
          className='form-control curl-download-command'
          value={downloadConfig.downloadCommand}
          readOnly
        />
        <span className='input-group-btn'>
            <Clipboard
              data-clipboard-target={'#command-' + downloadConfig.authCode}
              onSuccess={onSuccess}
              className='btn btn-default btn-copy'
              data-toggle='tooltip'
              button-title='Copy to clipboard'
            >
              <i className='far fa-copy'></i>
            </Clipboard>
          <button
            id={'refresh-button-' + downloadConfig.authCode}
            className='download-refresh-button btn btn-default btn-refresh glyphicon glyphicon-refresh'
            data-toggle='tooltip'
            title='Refresh download command'>
          </button>
        </span>
        </div>
      <div id="download-command-caption">
        Valid for one use within {' '}
        <span className='countdown' id={'countdown-' + downloadConfig.authCode}>
          {Math.floor(downloadConfig.timeInterval / 60)} {/* seconds -> minutes */}
        </span>{' '}
        minutes.  If your command has expired, click refresh button at right in this box.
      </div>
    </div>
  );
}


/**
 * Component for "Download" button and Bulk Download modal.
 *
 * UI spec: https://projects.invisionapp.com/d/main#/console/19272801/402387755/preview
 */
export default function DownloadButton(props) {

  const [show, setShow] = useState(false);

  function showModalAndFetchDownloadCommand() {
    setShow(!show);
  }

  const handleClose = () => setShow(false);

  return (
      <>
      <span id='download-button' className= {`${show ? 'active' : ''}`} className='facet'>
        <span onClick={showModalAndFetchDownloadCommand}>
          <FontAwesomeIcon className="icon-left" icon={faDownload}/>
          Download
        </span>
      </span>
      <Modal
        id='bulk-download-modal'
        show={show}
        onHide={handleClose}
        animation={false}
        bsSize='large'
      >
        <Modal.Header closeButton>
          <h2 className='text-center'>Bulk Download</h2>
        </Modal.Header>

        <Modal.Body>
          <p className='lead'>
          To download files matching your search, copy this command and paste it into your terminal:
          </p>
          <div className='lead command-container' id='command-container-all'>
            <DownloadCommandContainer />
          </div>
        </Modal.Body>

      </Modal>
      </>
    );
}