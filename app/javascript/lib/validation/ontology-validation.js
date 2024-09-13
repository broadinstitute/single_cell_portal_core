import { decompressSync, strFromU8 } from 'fflate'

import {
  metadataSchema, REQUIRED_CONVENTION_COLUMNS
} from './shared-validation'

const ONTOLOGY_BASE_URL =
  'https://raw.githubusercontent.com/broadinstitute/scp-ingest-pipeline/' +
  'development/ingest/validation/ontologies/'

/** Quickly retrieve current version cache key for ontologies */
async function fetchOntologyCacheVersion() {
  const response = await fetch(`${ONTOLOGY_BASE_URL}version.txt`)
  const text = await response.text()
  const version = text.trim().split('#')[0]
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
async function fetchGzipped(url) {
  const response = await fetch(url)
  const blob = await response.blob();
  const uint8Array = new Uint8Array(await blob.arrayBuffer());
  const plaintext = strFromU8(decompressSync(uint8Array));
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
      new Blob([data], { type: 'text/tab-separated-values' }),
      { headers: new Headers({ 'Content-Length': contentLength }) }
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

window.fetchOntologies = fetchOntologies

/** Get lowercase shortnames for all required ontologies */
function getOntologyShortNames() {
  let requiredOntologies = []

  // Validate IDs for species, organ, disease, and library preparation protocol
  for (let i = 0; i < REQUIRED_CONVENTION_COLUMNS.length; i++) {
    const column = REQUIRED_CONVENTION_COLUMNS[i]
    if (!column.endsWith('__ontology_label')) {continue}
    const key = column.split('__ontology_label')[0]
    const ontologies = getAcceptedOntologies(key, metadataSchema)
    requiredOntologies = requiredOntologies.concat(ontologies)
  }

  requiredOntologies = Array.from(
    new Set(requiredOntologies.map(o => o.toLowerCase()))
  )

  return requiredOntologies
}

/**
 * Get list of ontology names accepted for key from metadata schema
 *
 * E.g. "disease" -> ["MONDO", "PATO"]
 */
export function getAcceptedOntologies(key, metadataSchema) {
  // E.g. "ontology_browser_url": "https://www.ebi.ac.uk/ols/ontologies/mondo,https://www.ebi.ac.uk/ols/ontologies/pato"
  const olsUrls = metadataSchema.properties[key].ontology

  const acceptedOntologies =
    olsUrls?.split(',').map(url => url.split('/').slice(-1)[0].toUpperCase())

  if (acceptedOntologies.includes('NCBITAXON')) {
    acceptedOntologies.push('NCBITaxon')
  }

  return acceptedOntologies
}
