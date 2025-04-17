import { openH5File } from 'hdf5-indexed-reader'

import { getOAuthToken } from '~/lib/scp-api'
import {
  validateUnique, validateRequiredMetadataColumns,
  validateAlphanumericAndUnderscores, getOntologyShortNameLc,
  metadataSchema, REQUIRED_CONVENTION_COLUMNS
} from './shared-validation'
import { fetchOntologies, getOntologyBasedProps, getAcceptedOntologies } from './ontology-validation'

const ONTOLOGY_PROPS = getOntologyBasedProps()

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

/** Validate author's annotation labels and IDs match those in ontologies */
export async function checkOntologyLabelsAndIds(key, ontologies, groups) {
  const [ids, idIndexes, labels, labelIndexes] = groups

  const issues = []

  // Determine unique (ontology ID, ontology label) pairs
  const labelIdPairs = new Set()
  for (let i = 0; i < idIndexes.length; i++) {
    const id = ids[idIndexes[i]]
    const label = labels[labelIndexes[i]]
    labelIdPairs.add(`${id} || ${label}`)
  }
  const rawUniques = Array.from(labelIdPairs)

  rawUniques.map(r => {
    let [id, label] = r.split(' || ')
    const ontologyShortNameLc = getOntologyShortNameLc(id)
    const ontology = ontologies[ontologyShortNameLc]

    if (id.includes(':')) {
      // Convert colon to underscore for ontology lookup
      const idParts = id.split(':')
      id = `${idParts[0]}_${idParts[1]}`
    }
    if (!(id in ontology)) {
      // Register invalid ontology ID
      const msg = `Invalid ontology ID: ${id}`
      issues.push([
        'error', 'ontology:label-lookup-error', msg,
        { subtype: 'ontology:invalid-id' }
      ])
    } else {
      const validLabels = ontology[id]

      if (!(validLabels.includes(label))) {
        // Register invalid ontology label
        const prettyLabels = validLabels.join(', ')
        const validLabelsClause = `Valid labels for ${id}: ${prettyLabels}`
        const msg = `Invalid ${key} label "${label}".  ${validLabelsClause}`
        issues.push([
          'error', 'ontology:label-lookup-error', msg,
          { subtype: 'ontology:invalid-label' }
        ])
      }
    }
  })

  return issues
}

/** Get ontology ID values for key in AnnData file */
export async function getOntologyIdsAndLabels(columnName, hdf5File) {
  const obs = await hdf5File.get('obs')
  const obsValues = await Promise.all(obs.values)
  const isRequired = REQUIRED_CONVENTION_COLUMNS.includes(columnName)

  // Old versions of the AnnData spec used __categories as an obs.
  // However, in new versions (since before 2023-01-23) of AnnData spec,
  // categorical arrays are encoded as self-contained groups containing their
  // own `categories` and `codes`.
  // See e.g. https://github.com/scverse/anndata/issues/879
  const internalCategories = obsValues.find(o => o.name.endsWith('__categories'))
  if (internalCategories) {
    console.debug(
      'Encountered old-spec AnnData, skipping ontology label validation.  ' +
      'Server-side processing will validate this'
    )
    return null
  }

  const idKey = columnName
  const labelKey = `${columnName}__ontology_label`

  const idGroup = obsValues.find(o => o.name.endsWith(idKey))
  const labelGroup = obsValues.find(o => o.name.endsWith(labelKey))

  // exit when optional metadata isn't found, like cell_type
  if (!idGroup && !isRequired) { return }

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
  const idCategories = await idGroup.values[0]
  const idCodes = await idGroup.values[1]
  const ids = await idCategories.value
  const idIndexes = await idCodes.value

  const labelCategories = await labelGroup.values[0]
  const labelCodes = await labelGroup.values[1]
  const labels = await labelCategories.value
  const labelIndexes = await labelCodes.value

  return [ids, idIndexes, labels, labelIndexes]
}

/** Validate ontology labels for required metadata columns in AnnData file */
async function validateOntologyLabelsAndIds(hdf5File) {
  let issues = []

  const ontologies = await fetchOntologies()

  // Validate IDs for species, organ, disease, and library preparation protocol
  for (let i = 0; i < ONTOLOGY_PROPS.length; i++) {
    const column = ONTOLOGY_PROPS[i]
    const groups = await getOntologyIdsAndLabels(column, hdf5File)

    if (groups) {
      issues = issues.concat(
        await checkOntologyLabelsAndIds(column, ontologies, groups)
      )
    }
  }

  return issues
}


/** Validate ontology IDs for required metadata columns in AnnData file */
async function validateOntologyIdFormat(hdf5File) {
  let issues = []

  // Validate IDs for species, organ, disease, and library preparation protocol
  for (let i = 0; i < ONTOLOGY_PROPS.length; i++) {
    const column = ONTOLOGY_PROPS[i]
    const ontologyIds = await getOntologyIds(column, hdf5File)

    issues = issues.concat(
      checkOntologyIdFormat(column, ontologyIds)
    )
  }

  return issues
}

/** Parse AnnData file, and return an array of issues, along with file parsing info */
export async function parseAnnDataFile(fileOrUrl, remoteProps) {
  let issues = []

  const hdf5File = await getHdf5File(fileOrUrl, remoteProps)

  const headers = await getAnnDataHeaders(hdf5File)

  const requiredMetadataIssues = validateRequiredMetadataColumns([headers], true)
  let ontologyIdFormatIssues = []
  let ontologyLabelAndIdIssues = []
  if (requiredMetadataIssues.length === 0) {
    ontologyIdFormatIssues = await validateOntologyIdFormat(hdf5File)
    if (
      ontologyIdFormatIssues.length === 0 &&

      // TODO (SCP-5813): Enable ontology validation for remote AnnData
      remoteProps && 'url' in remoteProps === false
    ) {
      ontologyLabelAndIdIssues = await validateOntologyLabelsAndIds(hdf5File)
    }
  }

  issues = issues.concat(
    validateUnique(headers),
    validateAlphanumericAndUnderscores(headers),
    requiredMetadataIssues,
    ontologyIdFormatIssues,
    ontologyLabelAndIdIssues
  )

  return { issues }
}
