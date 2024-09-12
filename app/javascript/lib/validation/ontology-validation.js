import { decompressSync, strFromU8 } from 'fflate'

import {
  metadataSchema, REQUIRED_CONVENTION_COLUMNS
} from './shared-validation'

const ONTOLOGY_BASE_URL =
  'https://raw.githubusercontent.com/broadinstitute/scp-ingest-pipeline/' +
  'ew-refine-mini-ontologies/ingest/validation/ontologies/'

/** Fetch .gz file, decompress it, return plaintext */
async function fetchGzipped(url) {
  const response = await fetch(url)
  const blob = await response.blob();
  const uint8Array = new Uint8Array(await blob.arrayBuffer());
  const plaintext = strFromU8(decompressSync(uint8Array));
  return plaintext
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
async function fetchOntologies() {
  if (window.SCP.ontologies) {
    // Reuse fetched, processed ontologies from this page load
    return window.SCP.ontologies
  }

  const t0 = Date.now()
  const ontologies = {}

  const ontologyNames = getOntologyShortNames()

  for (let i = 0; i < ontologyNames.length; i++) {
    const ontologyName = ontologyNames[i]
    const ontologyUrl = `${ONTOLOGY_BASE_URL + ontologyName}.min.tsv.gz`
    const tsv = await fetchGzipped(ontologyUrl)

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

  const t1 = Date.now()
  console.log(t1-t0)

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
