import {openH5File} from 'hdf5-indexed-reader'

import {
  validateUnique, validateRequiredMetadataColumns,
  metadataSchema, REQUIRED_CONVENTION_COLUMNS
} from './shared-validation'
import { getOAuthToken } from '~/lib/scp-api'

// async function getValuesArray(key, hdf5File) {
//   const group = await hdf5File.get(key)
//   const rawValuePromises = await group.values
//   const headers = []
//   const valuesGroup = await Promise.all(rawValuePromises)
//   const valuesByArray = {}
//   const valuesGroup =
//   obsValues.forEach(obsValue => {
//     const annotationName = obsValue.name.split(`/${key}/`)[1]
//     headers.push(annotationName)
//   })
//   return headers
// }

/** Get ontology ID values for key in AnnData file */
async function getOntologyIds(key, hdf5File) {
  const obs = await hdf5File.get('obs')
  const obsValues = await Promise.all(obs.values)
  const group = obsValues.find(o => o.name.endsWith(key))
  let ontologyIds = null
  if (group) {
    const categories = await group.values[0]
    ontologyIds = await categories.value
  }
  return ontologyIds
}

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

/** Returns whether argument is an HTTP(S) URL */
function isUrl(fileOrUrl) {
  return typeof fileOrUrl === 'string' && fileOrUrl.startsWith('http')
}

/** Load local or remote AnnData file, return stream-parseable HDF5 object */
export async function getH5adFile(fileOrUrl, remoteProps) {
  // Jest test uses Node, where file API differs
  const isTest = isUrl(fileOrUrl)

  const isRemoteFileObject = !isUrl(fileOrUrl) && fileOrUrl.type === 'application/octet-stream'

  const idType = isTest || isRemoteFileObject ? 'url' : 'file'

  if (isRemoteFileObject) {
    fileOrUrl = remoteProps.url
  }

  const openParams = {}
  openParams[idType] = fileOrUrl

  if (isRemoteFileObject) {
    const oauthToken = getOAuthToken()
    openParams.oauthToken = oauthToken
  }

  const hdf5File = await openH5File(openParams)
  return hdf5File
}

/** Get all headers from AnnData file */
export async function getAnnDataHeaders(hdf5File) {
  const headers = await getAnnotationHeaders('obs', hdf5File)

  // const obsmHeaders = await getAnnotationHeaders('obsm', hdf5File)
  // const xHeaders = await getAnnotationHeaders('X', hdf5File)
  return headers
}

// /**  */
// async function validateDiseases(hdf5File) {
//   console.log('in validateDiseases')
//   let issues = []
//   const diseases = await getDiseases(hdf5File)
//   console.log('diseases')
//   console.log(diseases)
//   // "ontology_browser_url": "https://www.ebi.ac.uk/ols/ontologies/mondo,https://www.ebi.ac.uk/ols/ontologies/pato",
//   diseases.forEach(disease => {
//     const ontologyShortName = disease.split('_')[0]
//     console.log('ontologyShortName', ontologyShortName)
//     if (!['MONDO', 'PATO'].includes(ontologyShortName)) {
//       const msg = `Disease ID ${disease} is not among supported ontologies (MONDO, PATO)`
//       issues.push(['error', 'metadata:ontology', msg])
//     }
//   })
//   console.log('issues', issues)
//   return issues
// }

/**
 * Get list of ontology names accepted for key from metadata schema
 *
 * E.g. "disease" -> ["MONDO", "PATO"]
 */
function getAcceptedOntologies(key, metadataSchema) {
  // E.g. "ontology_browser_url": "https://www.ebi.ac.uk/ols/ontologies/mondo,https://www.ebi.ac.uk/ols/ontologies/pato"
  const olsUrls = metadataSchema.properties[key].ontology_browser_url

  const acceptedOntologies = olsUrls?.split(',').map(url => url.split('/').slice(-1)[0].toUpperCase())

  return acceptedOntologies
}

/** Validate ontology IDs for required metadata columns in AnnData file */
async function validateOntologyIdFormat(hdf5File) {
  const issues = []

  // Validate IDs for species, organ, disease, and library preparation protocol
  await REQUIRED_CONVENTION_COLUMNS.forEach(async column => {
    if (!column.endsWith('__ontology_label')) {return}
    const key = column.split('__ontology_label')[0]
    const ontologyIds = await getOntologyIds(key, hdf5File)

    const acceptedOntologies = getAcceptedOntologies(key, metadataSchema)
    if (!acceptedOntologies) {return}

    ontologyIds.forEach(ontologyId => {
      const ontologyShortName = ontologyId.split('_')[0]
      if (!acceptedOntologies.includes(ontologyShortName)) {
        const accepted = acceptedOntologies.join(', ')
        const msg =
          `Ontology ID "${ontologyId}" ` +
          `is not among accepted ontologies (${accepted}) ` +
          `for key "${key}"`
        issues.push(['error', 'metadata:ontology', msg])
      }
    })
  })

  return issues
}

/** Parse AnnData file, and return an array of issues, along with file parsing info */
export async function parseAnnDataFile(fileOrUrl, remoteProps) {
  let issues = []
  console.log('0')

  const hdf5File = await getH5adFile(fileOrUrl, remoteProps)

  const headers = await getAnnDataHeaders(hdf5File)
  console.log('headers')
  console.log(headers)

  // TODO (SCP-5770): Extend AnnData CSFV to remote files, then remove this
  if (!headers) {
    return { issues }
  }

  issues = issues.concat(
    validateUnique(headers),
    validateRequiredMetadataColumns([headers], true),
    await validateOntologyIdFormat(hdf5File)
  )

  return { issues }
}
