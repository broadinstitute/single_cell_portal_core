/**
* @fileoverview Client-side file validation (CSFV) for upload and sync
*
* Where feasible, these functions and data structures align with those in
* Ingest Pipeline [1].  Such consistency across codebases eases QA, debugging,
* and overall maintainability.
*
* [1] E.g. https://github.com/broadinstitute/scp-ingest-pipeline/blob/development/ingest/validation/validate_metadata.py
*/

import { readFileBytes, oneMiB } from './io'
import ChunkedLineReader, { GZIP_MAX_LINES } from './chunked-line-reader'
import { CSFV_VALIDATED_TYPES, UNVALIDATED_TYPES } from '~/components/upload/upload-utils'
import {
  parseDenseMatrixFile, parseFeaturesFile, parseBarcodesFile, parseSparseMatrixFile
} from './expression-matrices-validation'
import {
  getParsedHeaderLines, parseLine, ParseException,
  validateUniqueCellNamesWithinFile, validateMetadataLabelMatches,
  validateGroupColumnCounts, timeOutCSFV, validateUnique,
  validateRequiredMetadataColumns, validateAlphanumericAndUnderscores
} from './shared-validation'
import { parseDifferentialExpressionFile } from './validate-differential-expression'
import { parseAnnDataFile } from './validate-anndata'
import { fetchOntologies, getOntologyBasedProps } from '~/lib/validation/ontology-validation'
import { getOntologyShortNameLc, getLabelSuffixForOntology } from './shared-validation'

/**
 * Gzip decompression requires reading the whole file, given the current
 * approach in ChunkedLineReader.  To avoid consuming too much memory, this
 * limits CSFV to only processing gzipped files that are <= 50 MiB in
 * (compressed) size.  Because decompression currently reads whole file,
 * this means that chunk size === file size.  When decompressed, a 50 MiB
 * chunk can consume ~500 MiB in RAM.
 */
const MAX_GZIP_FILESIZE = 50 * oneMiB

/** File extensions / suffixes that indicate content must be gzipped */
const EXTENSIONS_MUST_GZIP = ['gz', 'bam', 'tbi', 'csi']
const ONTOLOGY_PROPS = getOntologyBasedProps()

/**
 * Helper function to verify first pair of headers is NAME or TYPE
 */
function validateKeyword(values, expectedValue) {
  const issues = []

  const ordinal = (expectedValue === 'NAME') ? 'First' : 'Second'
  const location = `${ordinal} row, first column`
  const value = values[0]
  const actual = `Your value was "${value}".`

  if (value.toUpperCase() === expectedValue) {
    if (value !== expectedValue) {
      const msg =
        `${location} should be ${expectedValue}. ${actual}`
      issues.push(['warn', 'format', msg])
    }
  } else {
    const msg =
      `${location} must be "${expectedValue}" (case insensitive). ${actual}`
    const logType = expectedValue?.toLowerCase()
    issues.push(['error', `format:cap:${logType}`, msg])
  }

  return issues
}

/**
 * Verify second row starts with NAME (case-insensitive)
 */
function validateNameKeyword(headers) {
  // eslint-disable-next-line max-len
  // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/0b6289dd91f877e5921a871680602d776271217f/ingest/annotations.py#L216
  return validateKeyword(headers, 'NAME')
}

/**
 * Verify second row starts with TYPE (case-insensitive)
 */
function validateTypeKeyword(annotTypes) {
  // eslint-disable-next-line max-len
  // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/0b6289dd91f877e5921a871680602d776271217f/ingest/annotations.py#L258
  return validateKeyword(annotTypes, 'TYPE')
}

/**
 * Verify type annotations (second row) contain only "group" or "numeric"
 */
function validateGroupOrNumeric(annotTypes) {
  const issues = []
  const badValues = []

  // Skip the TYPE keyword
  const types = annotTypes.slice(1)

  types.forEach(type => {
    if (!['group', 'numeric'].includes(type.toLowerCase())) {
      if (type === '') {
        // If the value is a blank space, store a higher visibility
        // string for error reporting
        badValues.push('<empty value>')
      } else {
        badValues.push(type)
      }
    }
  })

  // TODO (SCP-4128): Generalize this pattern across validation rules
  const valuesOrRows = 'values'
  const numBad = badValues.length
  if (numBad > 0) {
    const maxToShow = 100
    let notedBad = `"${badValues.slice(0, maxToShow).join('", "')}"`
    const numMore = numBad - maxToShow
    if (numMore > 0) {
      notedBad += ` and ${numMore - maxToShow} more ${valuesOrRows}`
    }

    const msg =
      'Second row, all columns after first must be "group" or "numeric". ' +
      `Your ${valuesOrRows} included ${notedBad}`

    issues.push(['error', 'format:cap:group-or-numeric', msg])
  }

  return issues
}

/**
 * Verify equal counts for headers and annotation types
 */
function validateEqualCount(headers, annotTypes) {
  const issues = []

  if (headers.length > annotTypes.length) {
    const msg =
      'First row must have same number of columns as second row. ' +
      `Your first row has ${headers.length} header columns and ` +
      `your second row has ${annotTypes.length} annotation type columns.`
    issues.push(['error', 'format:cap:count', msg])
  }

  return issues
}


/**
 * Verify cap format for a cluster or metadata file
 *
 * The "cap" of an SCP study file is its first "few" lines that contain structural data., i.e.:
 *  - Header (row 1), and
 *  - Annotation types (row 2)
 *
 * Cap lines are like meta-information lines in other file formats
 * (e.g. VCF), but do not begin with pound signs (#).
 */
function validateCapFormat([headers, annotTypes], isMetadataFile=true) {
  let issues = []
  if (!headers || !annotTypes) {
    return [['error', 'format:cap:no-cap-rows', 'File does not have 2 non-empty header rows']]
  }

  // Check format rules that apply to both metadata and (except one rule) cluster files
  issues = issues.concat(
    validateUnique(headers),
    validateAlphanumericAndUnderscores(headers, isMetadataFile),
    validateNameKeyword(headers),
    validateTypeKeyword(annotTypes),
    validateGroupOrNumeric(annotTypes),
    validateEqualCount(headers, annotTypes)
  )

  return issues
}

/** Verifies metadata file has no X, Y, or Z coordinate headers */
function validateNoMetadataCoordinates(headers) {
  const issues = []

  const invalidHeaders = headers[0].filter(header => {
    return ['x', 'y', 'z'].includes(header.toLowerCase())
  })

  if (invalidHeaders.length > 0) {
    const badValues = `"${invalidHeaders.join('", "')}"`
    const msg =
      'First row must not include coordinates X, Y, or Z ' +
      '(case insensitive) as column header values. ' +
      `Your values included ${badValues}.`
    issues.push(['error', 'format:cap:metadata-no-coordinates', msg])
  }

  return issues
}

/** Verifies cluster file has X and Y coordinate headers */
function validateClusterCoordinates(headers) {
  const issues = []

  const xyHeaders = headers[0].filter(header => {
    return ['x', 'y'].includes(header.toLowerCase())
  })

  if (xyHeaders.length < 2) {
    const msg =
      'First row must include coordinates X and Y ' +
      '(case insensitive) as column header values.'
    issues.push(['error', 'format:cap:cluster-coordinates', msg])
  }

  return issues
}


/** parse a metadata file, and return an array of issues, along with file parsing info */
export async function parseMetadataFile(chunker, mimeType, fileOptions) {
  const { headers, delimiter } = await getParsedHeaderLines(chunker, mimeType)
  let issues = validateCapFormat(headers)
  issues = issues.concat(validateNoMetadataCoordinates(headers))
  let ontologies
  // keep track of a map of ontology-based errors to avoid duplications
  const knownErrors = {}
  if (fileOptions.use_metadata_convention) {
    ontologies = await fetchOntologies()
    issues = issues.concat(validateRequiredMetadataColumns(headers))
  }

  // add other header validations here

  const dataObj = {} // object to track multi-line validation concerns
  await chunker.iterateLines({
    func: (rawline, lineNum, isLastLine) => {
      issues = issues.concat(timeOutCSFV(chunker))

      const line = parseLine(rawline, delimiter)
      issues = issues.concat(validateUniqueCellNamesWithinFile(line, isLastLine, dataObj))
      issues = issues.concat(validateMetadataLabelMatches(headers, line, isLastLine, dataObj))
      issues = issues.concat(validateGroupColumnCounts(headers, line, isLastLine, dataObj))
      if (fileOptions.use_metadata_convention) {
        issues = issues.concat(validateConventionTerms(headers, line, ontologies, knownErrors))
      }
    // add other line-by-line validations here
    }
  })
  return { issues, delimiter, numColumns: headers[0].length }
}

export function validateConventionTerms(headers, line, ontologies, knownErrors) {
  let issues = []
  const metadataHeaders = headers[0]
  for (let i = 0; i < metadataHeaders.length; i++) {
    const header = metadataHeaders[i]
    if (ONTOLOGY_PROPS.includes(header)) {
      const ontologyId = line[i]
      const labelHeader = `${header}${getLabelSuffixForOntology(ontologyId)}`
      const labelIdx = metadataHeaders.indexOf(labelHeader)
      const label = line[labelIdx]
      issues = issues.concat(validateOntologyTerm(header, ontologyId, label, ontologies, knownErrors))
    }
  }
  return issues
}

export function validateOntologyTerm(prop, ontologyId, label, ontologies, knownErrors) {
  const issues = []
  const ontologyShortNameLc = getOntologyShortNameLc(ontologyId)
  const ontology = ontologies[ontologyShortNameLc]

  if (ontologyId.includes(':')) {
    // Convert colon to underscore for ontology lookup
    const idParts = ontologyId.split(':')
    ontologyId = `${idParts[0]}_${idParts[1]}`
  }

  let errorIdentifier
  let issue

  if (!ontology) {
    errorIdentifier = `${ontologyId}-label-lookup-error`
    const accepted = Object.keys(ontologies).join(', ')
    const msg =
      `Ontology ID "${ontologyId}" ` +
      `is not among accepted ontologies (${accepted}) ` +
      `for key "${prop}"`

    issue = ['error', 'ontology:label-lookup-error', msg]
  } else if (!(ontologyId in ontology)) {
    // Register invalid ontology ID
    const msg = `Invalid ontology ID: ${ontologyId}`
    errorIdentifier = `${ontologyId}-invalid-id`
    issue = [
      'error', 'ontology:label-lookup-error', msg,
      { subtype: 'ontology:invalid-id' }
    ]
  } else {
    const validLabels = ontology[ontologyId]

    if (!(validLabels.includes(label))) {
      errorIdentifier = `${ontologyId}-label-lookup-error`
      // Register invalid ontology label
      const prettyLabels = validLabels.join(', ')
      const validLabelsClause = `Valid labels for ${ontologyId}: ${prettyLabels}`
      const msg = `Invalid ${prop} label "${label}".  ${validLabelsClause}`
      issue = [
        'error', 'ontology:label-lookup-error', msg,
        { subtype: 'ontology:invalid-label' }
      ]
    }
  }
  // only store unique instances of errors since we're validating line by line
  if (issue && typeof knownErrors[errorIdentifier] === 'undefined') {
    issues.push(issue)
    knownErrors[errorIdentifier] = true
  }
  return issues
}

/** parse a cluster file, and return an array of issues, along with file parsing info */
export async function parseClusterFile(chunker, mimeType) {
  const { headers, delimiter } = await getParsedHeaderLines(chunker, mimeType)
  let issues = validateCapFormat(headers, false)
  issues = issues.concat(validateClusterCoordinates(headers))
  // add other header validations here

  const dataObj = {} // object to track multi-line validation concerns
  await chunker.iterateLines({
    func: (rawLine, lineNum, isLastLine) => {
      issues = issues.concat(timeOutCSFV(chunker))

      const line = parseLine(rawLine, delimiter)
      issues = issues.concat(validateUniqueCellNamesWithinFile(line, isLastLine, dataObj))
      issues = issues.concat(validateGroupColumnCounts(headers, line, isLastLine, dataObj))
    // add other line-by-line validations here
    }
  })

  return { issues, delimiter, numColumns: headers[0].length }
}

/** Convert array of strings to a prose "or" or "and" phrase
 *
 * Example: prettyAndOr(['A', 'B', 'C'], 'or') > '"A", "B", or "C"' */
function prettyAndOr(stringArray, operator) {
  let phrase
  const quoted = stringArray.map(ext => `".${ext}"`)

  if (quoted.length === 1) {
    phrase = quoted[0]
  } else if (quoted.length === 2) {
    phrase = quoted.join(` ${operator} `)
    // e.g. "A" and "B"
  } else if (quoted.length > 2) {
    // e.g. "A", "B", or "C"
    const last = quoted.slice(-1)[0]
    phrase = `${quoted.slice(0, -1).join(', ')}, ${operator} ${last}`
  }

  return phrase
}

/** Confirm that the presence/absence of a .gz extension matches the lead byte of the file
 * Throws an exception if the gzip is conflicted, since we don't want to parse further in that case
*/
export async function validateGzipEncoding(file, fileType) {
  // skip check on any file type not included in CSFV
  if (UNVALIDATED_TYPES.includes(fileType) || fileType === 'AnnData') {
    return false
  }

  const GZIP_MAGIC_NUMBER = '\x1F'
  const fileName = file.name
  let isGzipped = null

  // read a single byte from the file to check the magic number
  const firstByte = await readFileBytes(file, 0, 1)

  const extension = fileName.split('.').slice(-1)[0]

  if (extension.toLowerCase() === 'rds') {
    // The R community often omits .gz extensions from gzip-compressed RDS files
    // More context: https://github.com/broadinstitute/single_cell_portal_core/pull/2145
    return false
  }

  const extensionMustGzip = EXTENSIONS_MUST_GZIP.includes(extension)

  if (extensionMustGzip) {
    if (firstByte === GZIP_MAGIC_NUMBER) {
      isGzipped = true
    } else {
      throw new ParseException('encoding:invalid-gzip-magic-number',
        `Files with extension "${extension}" must be gzipped; please gzip and retry`)
    }
  } else {
    if (firstByte === GZIP_MAGIC_NUMBER) {
      const prettyExts = prettyAndOr(EXTENSIONS_MUST_GZIP, 'or')
      const problem = `Only files with extensions ${prettyExts} may be gzipped`
      const solution = 'Please add a ".gz" extension to the file name, or decompress the file, and retry.'
      throw new ParseException('encoding:missing-gz-extension', `${problem}.  ${solution}`)
    } else {
      isGzipped = false
    }
  }
  return isGzipped
}

/**
 * Read File object, transform and validate it according to its SCP file type
 *
 * @returns {Object} result Validation results
 * @returns {Object} result.fileInfo Data about the file and its parsing
 * @returns {Object} result.issues Array of [category, type, message]
 * @returns {Number} result.perfTime How long this function took
 */
async function parseFile(
  file, fileType, fileOptions={},
  sizeProps={}, remoteProps={}, isAnnDataExperience
) {
  const startTime = performance.now()

  const fileInfo = {
    ...sizeProps,
    fileSize: file.size,
    fileName: file.name,
    linesRead: 0,
    numColumns: null,
    fileMimeType: file.type,
    fileType,
    delimiter: null,
    isGzipped: null
  }

  const parseResult = { fileInfo, issues: [] }

  // bypass validation for reference AnnData files
  if (fileType === 'AnnData' && !isAnnDataExperience) {
    parseResult.perfTime = Math.round(performance.now() - startTime)
    return parseResult
  }

  try {
    fileInfo.isGzipped = await validateGzipEncoding(file, fileType)
    // if the file is compressed or we can't figure out the compression, don't try to parse further
    const isFileFragment = file.size > sizeProps?.fileSizeTotal // likely a partial download from a GCP bucket

    if (
      !CSFV_VALIDATED_TYPES.includes(fileType) ||
      fileInfo.isGzipped && (isFileFragment || file.size >= MAX_GZIP_FILESIZE)
      // current gunzip implementation needs a whole file; see comment for MAX_GZIP_FILESIZE
    ) {
      return {
        fileInfo,
        issues: [],
        perfTime: Math.round(performance.now() - startTime)
      }
    }
    const parseFunctions = {
      'Cluster': parseClusterFile,
      'Metadata': parseMetadataFile,
      'Expression Matrix': parseDenseMatrixFile,
      '10X Genes File': parseFeaturesFile,
      '10X Barcodes File': parseBarcodesFile,
      'MM Coordinate Matrix': parseSparseMatrixFile,
      'Differential Expression': parseDifferentialExpressionFile
    }

    if (fileType === 'AnnData') {
      const { issues } = await parseAnnDataFile(file, remoteProps)
      parseResult.issues = parseResult.issues.concat(issues)
    } else if (parseFunctions[fileType]) {
      let ignoreLastLine = false
      if (sizeProps?.fetchedCompleteFile === false) {
        ignoreLastLine = true
        const msg =
          'Due to this file\'s size, it will be fully validated after sync, ' +
          'and any errors will be emailed to you.'

        parseResult.issues.push(['warn', 'incomplete:range-request', msg])
      }
      const chunker = new ChunkedLineReader(file, ignoreLastLine, fileInfo.isGzipped)

      const { issues, delimiter, numColumns, notes } =
        await parseFunctions[fileType](chunker, fileInfo.fileMimeType, fileOptions)
      fileInfo.linesRead = chunker.linesRead
      fileInfo.delimiter = delimiter
      fileInfo.numColumns = numColumns
      parseResult.issues = parseResult.issues.concat(issues)
      parseResult.notes = notes

      if (fileInfo.isGzipped && fileInfo.linesRead === GZIP_MAX_LINES + 1) {
        const msg =
        'Due to this file\'s size, it will be fully validated after upload, ' +
        'and any errors will be emailed to you.'

        parseResult.issues.push(['warn', 'incomplete:gzip-line-limit', msg])
      }
    }
  } catch (error) {
    // get any unhandled or deliberate short-circuits
    if (error instanceof ParseException) {
      parseResult.issues.push(['error', error.key, error.message])
    } else if (error instanceof TypeError) {
      const msg = 'File cannot be uploaded in its current state. Please reach out for assistance.'
      parseResult.issues.push(['error', 'parse:unhandled:js-typeerror', msg])
    } else {
      parseResult.issues.push(['error', 'parse:unhandled', error.message])
    }
    console.error(error)
  }

  const perfTime = Math.round(performance.now() - startTime)

  const issues = parseResult.issues
  const notes = parseResult.notes

  return {
    fileInfo,
    issues,
    perfTime,
    notes
  }
}

export default function ValidateFileContent() {
  return ''
}

ValidateFileContent.parseFile = parseFile
