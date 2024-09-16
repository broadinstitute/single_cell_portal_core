import {openH5File} from 'hdf5-indexed-reader'

import { getOAuthToken } from '~/lib/scp-api'
import {
  validateUnique, validateRequiredMetadataColumns,
  metadataSchema, REQUIRED_CONVENTION_COLUMNS
} from './shared-validation'
import { getAcceptedOntologies, fetchOntologies } from './ontology-validation'

/** Get ontology ID values for key in AnnData file */
async function getOntologyIds(key, hdf5File) {
  let ontologyIds = []

  const obs = await hdf5File.get('obs')
  const obsValues = await Promise.all(obs.values)

  // Old versions of the AnnData spec used __categories as an obs.
  // However, in new versions (since before 2023-01-23) of AnnData spec,
  // categorical arrays are encoded as self-contained groups containing their
  // own `categories` and `codes`.
  // See e.g. https://github.com/scverse/anndata/issues/879
  const internalCategories = obsValues.find(o => o.name.endsWith('__categories'))

  let resolvedCategories = obsValues
  if (internalCategories) {
    resolvedCategories = await Promise.all(internalCategories.values)
  }
  const group = resolvedCategories.find(o => o.name.endsWith(key))
  if (group) {
    let categories
    if (internalCategories) {
      ontologyIds = await group.value
    } else {
      categories = await group.values[0]
      ontologyIds = await categories.value
    }
  }

  return ontologyIds
}
window.getOntologyIds = getOntologyIds

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
export async function getHdf5File(fileOrUrl, remoteProps) {
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

/**
 * Check format of ontology IDs for key, return updated issues array
 *
 * TODO (SCP-5791): Move this rule to shared-validation.js, apply to classic as well
 */
export function checkOntologyIdFormat(key, ontologyIds) {
  const issues = []

  const acceptedOntologies = getAcceptedOntologies(key, metadataSchema)
  if (!acceptedOntologies) {return}

  ontologyIds.forEach(ontologyId => {
    const ontologyShortName = ontologyId.split(/[_:]/)[0]
    if (!acceptedOntologies.includes(ontologyShortName)) {
      const accepted = acceptedOntologies.join(', ')
      const msg =
        `Ontology ID "${ontologyId}" ` +
        `is not among accepted ontologies (${accepted}) ` +
        `for key "${key}"`

      // Match "ontology:label-lookup-error" error type used in Ingest Pipeline, per
      // https://github.com/broadinstitute/scp-ingest-pipeline/blob/858bb96ea7669f799d8f42d30b0b3131e2091710/ingest/validation/validate_metadata.py
      issues.push(['error', 'ontology:label-lookup-error', msg])
    }
  })

  return issues
}

/** Validate author's annotation labels match those in ontologies */
async function checkOntologyLabels(ids, idIndexes, labels, labelIndexes) {
  let issues = []

  const ontologies = await fetchOntologies()

  const labelIdPairs = []
  for (let i = 0; i < idIndexes.length; i++) {
    const id = ids[idIndexes[i]]
    // console.log('id', id)
    for (let j = 0; j < labelIndexes.length; j++) {
      const label = labels[labelIndexes[j]]
      // console.log('label', label)
      labelIdPairs.push(`${id} || ${label}`)
    }
  }
  const rawUniques = Array.from(new Set(labelIdPairs))

  rawUniques.map(r => {
    const [id, label] = r.split(' || ')
    const ontologyShortNameLc = id.split(/[_:]/)[0].toLowerCase()
    const ontology = ontologies[ontologyShortNameLc]
    if (!(id in ontology)) {
      const msg = `Invalid ontology ID: ${id}`
      issues.push([
        'error', 'ontology:label-lookup-error', msg,
        { subtype: 'ontology:invalid-id' }
      ])
    } else {
      const validLabels = ontology[id]
      if (!(validLabels.includes(label))) {
        const validLabelsClause = `Valid labels: ${validLabels.join(', ')}`
        const msg = `Invalid ontology label "${id}".  ${validLabelsClause}`
        issues.push([
          'error', 'ontology:label-lookup-error', msg,
          { subtype: 'ontology:invalid-label' }
        ])
      }
    }
})
}

/** Get ontology ID values for key in AnnData file */
async function getOntologyLabels(key, hdf5File) {
  let ontologyIds = []

  const obs = await hdf5File.get('obs')
  const obsValues = await Promise.all(obs.values)

  // Old versions of the AnnData spec used __categories as an obs.
  // However, in new versions (since before 2023-01-23) of AnnData spec,
  // categorical arrays are encoded as self-contained groups containing their
  // own `categories` and `codes`.
  // See e.g. https://github.com/scverse/anndata/issues/879
  const internalCategories = obsValues.find(o => o.name.endsWith('__categories'))

  let resolvedCategories = obsValues
  if (internalCategories) {
    resolvedCategories = await Promise.all(internalCategories.values)
  }
  const group = resolvedCategories.find(o => o.name.endsWith(key))
  if (group) {
    if (internalCategories) {
      ontologyIds = await group.value
    } else {
      // AnnData organizes each "obs" annotation (e.g. disease__ontology_label,
      // sex) into a container with a `categories` frame and a `code` frame.
      //
      // - categories: external values, non-redundant array. E.g.:
      //     ["tuberculosis", "TB", "foo"] or ["female"]
      //
      // - codes: internal values, redundant array of integers that specify
      //     the index (position) of each category value in the array of obs
      //     (cells)
      //
      // This organization greatly decreases filesize, but requires more code
      // to map paired obs annotations like `disease` (ontology IDs) to
      // `disease__ontology_label` (ontology names) than needed for e.g. TSVs.
      const categories = await group.values[0]
      ontologyIds = await categories.value

      const codes = await group.values[1]
      const indexes = await codes.value

    }
  }

  return ontologyIds
}

/** Validate ontology labels for required metadata columns in AnnData file */
async function validateOntologyLabels(hdf5File) {
  window.hdf5File = hdf5File
  let issues = []

  return issues

  // Validate IDs for species, organ, disease, and library preparation protocol
  for (let i = 0; i < REQUIRED_CONVENTION_COLUMNS.length; i++) {
    const column = REQUIRED_CONVENTION_COLUMNS[i]
    if (!column.endsWith('__ontology_label')) {continue}
    const key = column.split('__ontology_label')[0]
    const ontologyIds = await getOntologyIds(key, hdf5File)

    issues = issues.concat(
      checkOntologyIdFormat(key, ontologyIds)
    )
  }

  return issues
}


/** Validate ontology IDs for required metadata columns in AnnData file */
async function validateOntologyIdFormat(hdf5File) {
  let issues = []

  // Validate IDs for species, organ, disease, and library preparation protocol
  for (let i = 0; i < REQUIRED_CONVENTION_COLUMNS.length; i++) {
    const column = REQUIRED_CONVENTION_COLUMNS[i]
    if (!column.endsWith('__ontology_label')) {continue}
    const key = column.split('__ontology_label')[0]
    const ontologyIds = await getOntologyIds(key, hdf5File)

    issues = issues.concat(
      checkOntologyIdFormat(key, ontologyIds)
    )
  }

  return issues
}

/** Parse AnnData file, and return an array of issues, along with file parsing info */
export async function parseAnnDataFile(fileOrUrl, remoteProps) {
  let issues = []

  const hdf5File = await getHdf5File(fileOrUrl, remoteProps)

  const headers = await getAnnDataHeaders(hdf5File)

  // TODO (SCP-5770): Extend AnnData CSFV to remote files, then remove this
  if (!headers) {
    return { issues }
  }

  const requiredMetadataIssues = validateRequiredMetadataColumns([headers], true)
  let ontologyIdFormatIssues = []
  let ontologyLabelIssues = []
  if (requiredMetadataIssues.length === 0) {
    ontologyIdFormatIssues = await validateOntologyIdFormat(hdf5File)
    if (ontologyIdFormatIssues.length === 0) {
      ontologyLabelIssues = await validateOntologyLabels(hdf5File)
    }
  }

  issues = issues.concat(
    validateUnique(headers),
    requiredMetadataIssues,
    ontologyIdFormatIssues
  )

  return { issues }
}
