import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDownload } from '@fortawesome/free-solid-svg-icons'
import Modal from 'react-bootstrap/lib/Modal'
import Tooltip from 'react-bootstrap/lib/Tooltip'
import OverlayTrigger from 'react-bootstrap/lib/OverlayTrigger'

import {
  useContextStudySearch, hasSearchParams
} from 'providers/StudySearchProvider'
import { useContextUser } from 'providers/UserProvider'
import { useContextDownload } from 'providers/DownloadProvider'
import { fetchAuthCode } from 'lib/scp-api'

/**
 * Fetch auth code, build download command, return configuration object
 *
 * @returns {Object} Object for auth code, time interval, and download command
 */
async function generateDownloadConfig(matchingAccessions) {
  const accessions = matchingAccessions.join(',')
  const searchQuery = `&file_types=metadata,expression&accessions=${accessions}`

  const { authCode, timeInterval } = await fetchAuthCode()

  const queryString = `?auth_code=${authCode}${searchQuery}`

  // Gets a curl configuration ("cfg.txt") containing signed
  // URLs and output names for all files in the download object.
  const baseUrl = `${window.origin}/single_cell/api/v1/`
  const url = `${baseUrl}search/bulk_download${queryString}`

  // "-k" === "--insecure"
  let curlSecureFlag = ''
  if (('SCP' in window) && window.location.host === 'localhost') {
    curlSecureFlag = 'k'
  }

  // This is what the user will run in their terminal to download the data.
  // To consider: check the node environment (either at compile or runtime)
  // instead of the hostname
  const downloadCommand = (
    `curl "${url}" -${curlSecureFlag}o cfg.txt; ` +
    `curl -K cfg.txt; rm cfg.txt`
  )

  return {
    authCode,
    timeInterval,
    downloadCommand
  }
}

/**
 * Container for curl command to download files
 */
function DownloadCommandContainer(props) {
  const [downloadConfig, setDownloadConfig] = useState({})
  const textInputRef = useRef(null)

  // eweitz 2020-03-19: WIP to show "Copied!" on clipboard copy button click
  // const [copyTooltipText, setCopyTooltipText] = useState('Copy to clipboard')
  // const [target, setTarget] = useState(null)

  // const copyButtonRef = useRef(null)

  /**
   * Fetch new download command, update state accordingly
   */
  async function updateDownloadConfig(matchingStudies) {
    const fetchData = async () => {
      const dlConfig = await generateDownloadConfig(matchingStudies)
      setDownloadConfig(dlConfig)
    }
    fetchData()
  }

  useEffect(() => {
    updateDownloadConfig(props.matchingAccessions)
  }, [])

  /** Copy download command to user's system clipboard */
  function copyToClipboard(event) {
    // setCopyTooltipText('Copied!')
    textInputRef.current.select()
    document.execCommand('copy')
    event.target.focus()
    // copyButtonRef.current.select()
  }

  return (
    'authCode' in downloadConfig &&
    <div>
      <div className='input-group'>
        <input
          id={`command-${downloadConfig.authCode}`}
          ref={textInputRef}
          className='form-control curl-download-command'
          value={downloadConfig.downloadCommand || ''}
          readOnly
        />
        <span className='input-group-btn'>
          {/*
            eweitz 2020-03-19:
            WIP to show "Copied!" on click.  This is commented out because
            that text transiently shifts ~30px to the left; not sure why.
            Uncomment `OverlayTrigger` and `setCopyTooltipText` to experiment.
          */}
          {/*
            <OverlayTrigger
            placement='top'
            target={target}
            delay={{ hide: 400 }}
            overlay={<Tooltip id='copy-tooltip'>{copyTooltipText}</Tooltip>}
          > */}
          <button
            className='btn btn-default btn-copy'
            onClick={event => {copyToClipboard(event)}}
            data-toggle='tooltip'
            title='Copy to clipboard'
            // ref={copyButtonRef}
          >
            <i className='far fa-copy'></i>
          </button>
          {/* </OverlayTrigger> */}
          <button
            id={`refresh-button-${downloadConfig.authCode}`}
            className='download-refresh-button btn btn-default btn-refresh glyphicon glyphicon-refresh' // eslint-disable-line max-len
            data-toggle='tooltip'
            title='Refresh download command'
            onClick={() => {
              updateDownloadConfig(props.matchingAccessions)
              // setCopyTooltipText('Copy to clipboard')
            }}
          >
          </button>
        </span>
      </div>
      <div id="download-command-caption">
        Valid for one use within {' '}
        <span className='countdown' id={`countdown-${downloadConfig.authCode}`}>
          {Math.floor(downloadConfig.timeInterval / 60)}
        </span>{' '}
        minutes.  If your command has expired, click refresh button at right
        in this box.
      </div>
    </div>
  )
}

/**
 * Format number in bytes, with human-friendly units
 *
 * Derived from https://gist.github.com/lanqy/5193417#gistcomment-2663632
 */
function bytesToSize(bytes) {
  const sizes = ['bytes', 'KB', 'MB', 'GB', 'TB']
  if (bytes === 0) return 'n/a'

  // eweitz: Most implementations use log(1024), but such units are
  // binary and have values like MiB (mebibyte)
  const i = parseInt(Math.floor(Math.log(bytes) / Math.log(1000)), 10)

  if (i === 0) return `${bytes} ${sizes[i]}`
  return `${(bytes / (1000 ** i)).toFixed(1)} ${sizes[i]}`
}

/**
 * Get introductory text for download command, including download size
 *
 * @param {Object} downloadSize Size in bytes, by file type
 */
function getLeadText(downloadSize) {
  // Sum sizes by file type to total size for download
  const totalSize =
    Object.values(downloadSize).reduce((prevSize, sizeObj) => {
      return sizeObj.total_bytes + prevSize
    }, 0)
  const prettyBytes = bytesToSize(totalSize)

  // Get file type summary
  // E.g. "metadata and expression" or
  // (possibly later) "metadata, cluster, and expression"
  const ft = Object.keys(downloadSize)
  let fileTypes = ft.join(' and ')
  if (ft.length > 2) {
    const allButLast = ft.slice(0, -1)
    const last = ft.slice(-1)[0]
    fileTypes = `${allButLast.join(', ')}, and ${last}`
  }

  return (`
    To download ${prettyBytes} in ${fileTypes} files
    matching your search, copy this command and paste it into your terminal:
  `)
}

/**
 * Component for "Download" button and Bulk Download modal.
 *
 * UI spec: https://projects.invisionapp.com/d/main#/console/19272801/402387755/preview
 */
export default function DownloadButton(props) {
  const searchContext = useContextStudySearch()
  const userContext = useContextUser()
  const downloadContext = useContextDownload({ results: searchContext.results })

  const [show, setShow] = useState(false)

  const matchingAccessions = searchContext.results.matchingAccessions || []
  const downloadSize = downloadContext.downloadSize

  /**
   * Reports whether Download button should be active,
   * i.e. user is signed in, has search results,
   * and search has parameters (i.e. user would not download all studies)
   * and download context (i.e. download size preview) has loaded
   */
  const active = (
    userContext.accessToken !== '' &&
    matchingAccessions.length > 0 &&
    hasSearchParams(searchContext.params) &&
    downloadContext.isLoaded
  )

  let hint = 'Download files for your search results'
  if (!active) {
    if (userContext.accessToken === '') {
      hint = 'To download, please sign in'
    } else {
      hint = 'To download, first do a search'
    }
  }

  const handleClose = () => setShow(false)

  return (
    <>
      <OverlayTrigger
        placement='top'
        overlay={<Tooltip id='download-tooltip'>{hint}</Tooltip>}>
        <button
          id='download-button'
          className={`btn btn-primary ${active ? 'active' : 'disabled'}`}>
          <span onClick={() => {setShow(true)}}>
            <FontAwesomeIcon className="icon-left" icon={faDownload}/>
          Download
          </span>
        </button>
      </OverlayTrigger>
      <Modal
        id='bulk-download-modal'
        show={show}
        onHide={handleClose}
        animation={false}
        bsSize='large'>
        <Modal.Header closeButton>
          <h2 className='text-center'>Bulk Download</h2>
        </Modal.Header>
        <Modal.Body>
          <p className='lead'>
            {getLeadText(downloadSize)}
          </p>
          <div className='lead command-container' id='command-container-all'>
            <DownloadCommandContainer
              matchingAccessions={matchingAccessions}
            />
          </div>
        </Modal.Body>

      </Modal>
    </>
  )
}
