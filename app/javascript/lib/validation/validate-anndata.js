import {openH5File} from '@single-cell-portal/hdf5-indexed-reader'

import { validateUnique, validateRequiredMetadataColumns } from './shared-validation'

/** Get annotation headers for a key (e.g. obs) from an HDF5 file */
async function getAnnotationHeaders(key, hdf5File) {
  const obsGroup = await hdf5File.get(key)
  const rawObsValues = await obsGroup.values
  const headers = []
  const obsValues = await Promise.all(rawObsValues)
  obsValues.forEach(obsValue => {
    const annotationName = obsValue.name.split(`/${key}/`)[1]
    headers.push(annotationName)
  })
  return headers
}

/** Get all headers from AnnData file */
async function getAnnDataHeaders(file) {
  // TODO: Parameterize this, also support URL to remote file
  const idType = file.type === 'application/octet-stream' ? 'url' : 'file'

  // TODO (SCP-5770): Extend AnnData CSFV to remote files, then remove this
  if (idType === 'url') {
    return null
  }

  const openParams = {}
  openParams[idType] = file
  const hdf5File = await openH5File(openParams)

  const headers = await getAnnotationHeaders('obs', hdf5File)

  // const obsmHeaders = await getAnnotationHeaders('obsm', hdf5File)
  // const xHeaders = await getAnnotationHeaders('X', hdf5File)
  return headers
}

/** Parse AnnData file, and return an array of issues, along with file parsing info */
export async function parseAnnDataFile(file) {
  const headers = await getAnnDataHeaders(file)

  // TODO (SCP-5770): Extend AnnData CSFV to remote files, then remove this
  if (!headers) {return []}

  let issues = []

  issues = issues.concat(
    validateUnique(headers),
    validateRequiredMetadataColumns([headers], true)
  )

  return { issues }
}
