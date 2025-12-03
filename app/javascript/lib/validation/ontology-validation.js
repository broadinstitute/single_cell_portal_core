/**
 * @fileoverview Validates ontology labels and IDs in files added by users
 *
 * SCP requires cells to have certain metadata annotations, e.g.
 * species, organ, disease, and library preparation protocol.  This module
 * loads ontology reference data, and uses it to check required cell metadata
 * in the user's uploaded or transferred file.
 *
 * More context, demo:
 * https://github.com/broadinstitute/single_cell_portal_core/pull/2129
 */

import { decompressSync, strFromU8 } from 'fflate'

import { metadataSchema } from './shared-validation'

// TODO: Replace "development" with "main" after next ingest release
const ONTOLOGY_BASE_URL =
  'https://raw.githubusercontent.com/broadinstitute/scp-ingest-pipeline/' +
  'main/ingest/validation/ontologies/'

/** Quickly retrieve current version cache key for ontologies */
async function fetchOntologyCacheVersion() {
  if (window.SCP.ontologiesVersion) { return window.SCP.ontologiesVersion }
  const response = await fetch(`${ONTOLOGY_BASE_URL}version.txt`)
  const text = await response.text()
  const version = text.trim().split('#')[0]
  window.SCP.ontologiesVersion = version
  return version
}

/** Get frontend SW cache object for minified ontologies */
async function getServiceWorkerCache() {
  const version = await fetchOntologyCacheVersion()
  const currentOntologies = `ontologies-${version}`

  // Delete other versions of ontologies cache; there should be 1 per dodmain
  const cacheNames = await caches.keys()
  cacheNames.forEach(name => {
    if (name.startsWith('ontologies-') && name !== currentOntologies) {
      caches.delete(name)
    }
  })

  const cache = await caches.open(currentOntologies)

  return cache
}

/** Fetch .gz file, decompress it, return plaintext */
export async function fetchGzipped(url) {
  const response = await fetch(url)
  const blob = await response.blob()
  const uint8Array = new Uint8Array(await blob.arrayBuffer())
  const plaintext = strFromU8(decompressSync(uint8Array))
  return plaintext
}

/** Fetch from service worker cache if available, from remote otherwise */
export async function cacheFetch(url) {
  const cache = await getServiceWorkerCache()

  const decompressedUrl = url.replace('.gz', '')
  const response = await cache.match(decompressedUrl)
  if (typeof response === 'undefined') {
    // If cache miss, then fetch, decompress, and put response in cache
    const data = await fetchGzipped(url)
    const contentLength = data.length
    const decompressedResponse = new Response(
      data,
      {
        headers: new Headers({
          'Content-Length': contentLength,
          'Content-Type': 'text/tab-separated-values'
        })
      }
    )
    await cache.put(decompressedUrl, decompressedResponse)
    return await cache.match(decompressedUrl)
  }
  return await cache.match(decompressedUrl)
}

/**
 * Fetch minified ontologies, transform into object of object of arrays, e.g.:
 *
 * {
 *   'mondo': {
 *     'MONDO_0008315': ['prostate cancer', 'prostate neoplasm', 'prostatic neoplasm'],
 *     'MONDO_0018076': ['tuberculosis', 'TB'],
 *     ...
 *   },
 *   'ncbitaxon': {
 *     'NCBITaxon_9606': ['Homo sapiens', 'human'],
 *     'NCBITaxon_10090': ['Mus musculus', 'house mouse', 'mouse'],
 *     ...
 *   },
 *   ...
 * }
 */
export async function fetchOntologies() {
  if (window.SCP.ontologies) {
    // Reuse fetched, processed ontologies from this page load
    return window.SCP.ontologies
  }

  const ontologies = {}

  const ontologyNames = getOntologyShortNames()

  for (let i = 0; i < ontologyNames.length; i++) {
    const ontologyName = ontologyNames[i]
    const ontologyUrl = `${ONTOLOGY_BASE_URL + ontologyName}.min.tsv.gz`
    const response = await cacheFetch(ontologyUrl)

    const tsv = await response.text()
    const lines = tsv.split('\n')

    ontologies[ontologyName] = {}

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      const [ontologyId, label, rawSynonyms] = line.split('\t')
      let names = [label]
      if (rawSynonyms) {
        const synonyms = rawSynonyms.split('||')
        names = names.concat(synonyms)
      }
      ontologies[ontologyName][ontologyId] = names
    }
  }

  window.SCP.ontologies = ontologies
  return ontologies
}

/** Get lowercase shortnames for all supported ontologies */
export function getOntologyShortNames() {
  let supportedOntologies = []

  // get all ontology-based properties, ignoring organ_region as it isn't minified
  const properties = getOntologyBasedProps()
  for (let i = 0; i < properties.length; i++) {
    const prop = properties[i]
    const ontologies = getAcceptedOntologies(prop, metadataSchema)
    supportedOntologies = supportedOntologies.concat(ontologies)
  }
  return Array.from(new Set(supportedOntologies.map(o => o.toLowerCase())))
}

/** get all metadata properties that are ontology-based */
export function getOntologyBasedProps() {
  const ontologyProps = []
  // ignore organ_region as it isn't a supported minified ontology
  const properties = Object.keys(metadataSchema.properties).filter(p => p !== 'organ_region')
  for (let i = 0; i < properties.length; i++) {
    const prop = properties[i]
    if (metadataSchema.properties[prop].ontology) {
      ontologyProps.push(prop)
    }
  }
  return ontologyProps
}

/**
 * Get list of ontology names accepted for key from metadata schema
 *
 * E.g. "disease" -> ["MONDO", "PATO"]
 */
export function getAcceptedOntologies(key, metadataSchema) {
  // E.g. "ontology_browser_url": "https://www.ebi.ac.uk/ols/ontologies/mondo,https://www.ebi.ac.uk/ols/ontologies/pato"
  const olsUrls = metadataSchema.properties[key]?.ontology

  const acceptedOntologies =
    olsUrls?.split(',').map(url => url.split('/').slice(-1)[0].toUpperCase())

  if (acceptedOntologies && acceptedOntologies.includes('NCBITAXON')) {
    acceptedOntologies.push('NCBITaxon')
  }

  return acceptedOntologies
}

/**
 * fetch a remote ontology term from OLS for NCBI taxon IDs
 * @param termId {String} ontology term ID, e.g. "NCBITaxon_9606"
 * @returns {Object, null} JSON of ontology term, if found
 */
export async function fetchOlsOntologyTerm(termId) {
  const noMatch = {}
  noMatch[termId] = 'Not found'
  try {
    const ontologyName = termId.split('_')[0].toLowerCase()
    const purlIri = `http://purl.obolibrary.org/obo/${termId}`
    // purl IRI values must be double-encoded, to match behavior in:
    // https://github.com/broadinstitute/scp-ingest-pipeline/blob/development/ingest/validation/validate_metadata.py#L348
    const termUrl = `https://www.ebi.ac.uk/ols4/api/ontologies/${ontologyName}/` +
                            `terms/${encodeURIComponent(encodeURIComponent(purlIri))}?lang=en`
    console.debug(`termUrl: ${termUrl}`)
    const rawTerm = await fetch(termUrl)
    console.debug(`rawTerm: ${JSON.stringify(rawTerm)}`)
    if (rawTerm.ok) {
      return rawTerm.json()
    } else {
      return noMatch
    }
  } catch (error) {
    return noMatch
  }
}
