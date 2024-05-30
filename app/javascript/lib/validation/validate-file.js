/**
 * @fileoverview Client-side file validation (CSFV) for upload and sync UI
 */

import { oneGiB, oneMiB } from '~/lib/validation/io'
import ValidateFileContent from './validate-file-content'
import { logFileValidation } from './log-validation'
import { fetchBucketFile } from '~/lib/scp-api'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'


/** take an array of [category, type, msg] issues, and format it */
function formatIssues(issues) {
  const errors = issues.filter(issue => issue[0] === 'error')
  const warnings = issues.filter(issue => issue[0] === 'warn')

  return { errors, warnings }
}

/** Validate name uniqueness and file extension */
function validateFileName(file, studyFile, allStudyFiles, allowedFileExts=['*']) {
  const otherFiles = allStudyFiles.filter(f => f._id != studyFile._id)
  const otherNames = otherFiles.map(f => f.name)
  const otherUploadFileNames = otherFiles.map(f => f.upload_file_name)
  const otherLocalFileNames = otherFiles.map(f => f.uploadSelection?.name)

  const issues = []

  if (otherNames.includes(file.name) ||
    otherUploadFileNames.includes(file.name) ||
    otherLocalFileNames.includes(file.name)) {
    const msg = `A file named ${file.name} already exists in your study`
    issues.push(['error', 'filename:duplicate', msg])
  }

  if (!allowedFileExts.includes('*') && !allowedFileExts.some(ext => file.name.endsWith(ext))) {
    const msg = `Allowed extensions are ${allowedFileExts.join(', ')}`
    issues.push(['error', 'filename:extension', msg])
  }

  return issues
}

/** checks name uniqueness, file extension, and then file content.
 * The first two checks short-circuit the latter, since those will often just mean the user
 * has local the wrong file, and showing a string of validation errors would be confusing
 * @param file {File} the File object from the input
 * @param studyFile {StudyFile} the JS object corresponding to the StudyFile
 * @param allStudyFiles {StudyFile[]} the array of all files for the study, used for name uniqueness checks
 * @param allowedFileExts { String[] } array of allowable extensions, ['*'] for all
 */
async function validateLocalFile(file, studyFile, allStudyFiles=[], allowedFileExts=['*']) {
  // if clientside file validation feature flag is false skip validation
  const flags = getFeatureFlagsWithDefaults()
  if (flags && flags.clientside_validation === false) {
    const issues = formatIssues([])
    return [issues, {}]
  }
  const nameIssues = validateFileName(file, studyFile, allStudyFiles, allowedFileExts)

  let issuesObj
  let notesObj

  const noContentValidationFileTypes = ['Seurat', 'AnnData', 'Other', 'Documentation']

  const studyFileType = studyFile.file_type

  // Do not continue the validation if the file type is a non-viz type
  if (nameIssues.length === 0 && !noContentValidationFileTypes.includes(studyFileType)) {
    const fileOptions = {
      use_metadata_convention: studyFile.use_metadata_convention
    }
    const { fileInfo, issues, perfTime, notes } =
      await ValidateFileContent.parseFile(file, studyFileType, fileOptions)

    const allIssues = issues.concat(nameIssues)
    issuesObj = formatIssues(allIssues)
    notesObj = notes

    const perfTimes = {
      perfTime,
      'perfTime:parseFile': perfTime
    }

    logFileValidation(fileInfo, issuesObj, perfTimes)
  } else {
    issuesObj = formatIssues(nameIssues)
  }

  if (file.size >= oneGiB) {
    issuesObj.infos = [['info', 'size:large', '']]
  }

  return [issuesObj, notesObj]
}


/*
* 50 MiB, max number of bytes to read and validate from remote file for sync.
* Median fixed US bandwidth is 16 MiB/s (17 MB/s, 136 Mbps) as of 2021-12
* per https://www.speedtest.net/global-index/united-states.  > 80% of ingests
* are for files <= 50 MiB per https://mixpanel.com/s/3EbFMj.
*
* So 50 MiB means sync CSFV fully scans > 80% files, usually in < 5 seconds.
* Local tests gave 4.6 s (3.4 s remote read, 1.1 s validate; 138 Mbps down).
*/
const MAX_SYNC_CSFV_BYTES = 50 * oneMiB

/** Get file-size data for sync validation processing and logging */
function getSizeProps(contentRange, contentLength, file) {
  // Total size of the file in bytes
  let fileSizeTotal

  // Total bytes downloaded, which can be much less than total file size
  let fileSizeFetched

  if (contentRange !== null) {
    fileSizeTotal = parseInt(contentRange.split('/')[1])
    fileSizeFetched = parseInt(contentLength)
  } else {
    fileSizeTotal = file.size
    fileSizeFetched = fileSizeTotal
  }

  const fetchedCompleteFile = (fileSizeTotal === fileSizeFetched)

  return {
    fileSizeFetched,
    fileSizeTotal,
    fetchedCompleteFile
  }
}

/**
* Validate file in GCS bucket, log and return issues for sync UI
*
*  @param {String} bucketName Name of Google Cloud Storage bucket
*  @param {String} fileName Name of file object in GCS bucket
*  @param {String} fileType SCP file type
*  @param {Object} [fileOptions]
*
* @return {Object} issueObj Validation results, where:
*   - `errors` is an array of errors,
*   - `warnings` is an array of warnings, and
*   - `summary` is a message like "Your file had 2 errors"
*/
async function validateRemoteFile(
  bucketName, fileName, fileType, fileOptions
) {
  const startTime = performance.now()

  const requestStart = performance.now()
  // special handling for AnnData to only read 100 bytes of file
  // since we're not validating, we're just determining if the file exists
  const maxBytes = fileType === 'AnnData' ? 100 : MAX_SYNC_CSFV_BYTES
  const response = await fetchBucketFile(bucketName, fileName, maxBytes)
  let fileInfo; let issues; let perfTime; let readRemoteTime
  if (response.ok) {
    const content = await response.text()
    readRemoteTime = Math.round(performance.now() - requestStart)

    const contentRange = response.headers.get('content-range')
    const contentLength = response.headers.get('content-length')
    const contentType = response.headers.get('content-type')

    const file = new File([content], fileName, { type: contentType })

    const sizeProps = getSizeProps(contentRange, contentLength, file)

    // Equivalent block exists in validateFileContent
    const parseResults = await ValidateFileContent.parseFile(file, fileType, fileOptions, sizeProps)
    fileInfo = parseResults['fileInfo']
    issues = parseResults['issues']
    perfTime = parseResults['perfTime']
  } else {
    readRemoteTime = Math.round(performance.now() - requestStart)
    fileInfo = { fileName, linesRead: 0 }
    issues = [
      [
        'warn', 'file:access-failure', 'Unable to access the requested file. It will be fully validated after saving, ' +
        'and any errors will be emailed to you.'
      ]
    ]
  }

  const issuesObj = formatIssues(issues)

  const totalTime = Math.round(performance.now() - startTime)
  const perfTimes = {
    'perfTime': totalTime,
    'perfTime:parseFile': perfTime, // Processed parse + validate
    'perfTime:readRemote': readRemoteTime, // Fetch + raw parse
    'perfTime:other': totalTime - readRemoteTime - perfTime
  }

  logFileValidation(fileInfo, issuesObj, perfTimes)

  return issuesObj
}

export default function ValidateFile() {
  return ''
}

ValidateFile.validateLocalFile = validateLocalFile

ValidateFile.validateRemoteFile = validateRemoteFile
ValidateFile.getSizeProps = getSizeProps
ValidateFile.MAX_SYNC_CSFV_BYTES = MAX_SYNC_CSFV_BYTES
