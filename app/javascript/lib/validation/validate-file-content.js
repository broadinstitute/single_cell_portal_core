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
import { PARSEABLE_TYPES } from '~/components/upload/upload-utils'
import {
  parseDenseMatrixFile, parseFeaturesFile, parseBarcodesFile, parseSparseMatrixFile
} from './expression-matrices-validation'
import {
  getParsedHeaderLines, parseLine, ParseException,
  validateUniqueCellNamesWithinFile, validateMetadataLabelMatches, validateGroupColumnCounts, timeOutCSFV
} from './shared-validation'

// from lib/assets/metadata_schemas/alexandria_convention_schema.json
// (which in turn is from scp-ingest-pipeline/schemas)
export const REQUIRED_CONVENTION_COLUMNS = [
  'biosample_id',
  'disease',
  'disease__ontology_label',
  'donor_id',
  'library_preparation_protocol',
  'library_preparation_protocol__ontology_label',
  'organ',
  'organ__ontology_label',
  'sex',
  'species',
  'species__ontology_label'
]


/**
 * Gzip decompression requires reading the whole file, given the current
 * approach in ChunkedLineReader.  To avoid consuming too much memory, this
 * limits CSFV to only processing gzipped files that are <= 50 MiB in
 * (compressed) size.  Because decompression currently reads whole file,
 * this means that chunk size === file size.  When decompressed, a 50 MiB
 * chunk can consume ~500 MiB in RAM.
 */
const MAX_GZIP_FILESIZE = 50 * oneMiB

/**
 * Verify headers are unique and not empty
 */
function validateUnique(headers) {
  // eslint-disable-next-line max-len
  // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/0b6289dd91f877e5921a871680602d776271217f/ingest/annotations.py#L233
  const issues = []
  const uniques = new Set(headers)

  // Are headers unique?
  if (uniques.size !== headers.length) {
    const seen = new Set()
    const duplicates = new Set()
    headers.forEach(header => {
      if (seen.has(header)) {duplicates.add(header)}
      seen.add(header)
    })

    const dupString = [...duplicates].join(', ')
    const msg = `Duplicate header names are not allowed: ${dupString}`
    issues.push(['error', 'format:cap:unique', msg])
  }

  // Are all headers non-empty?
  if (uniques.has('')) {
    const msg = 'Headers cannot contain empty values'
    issues.push(['error', 'format:cap:no-empty', msg])
  }

  return issues
}

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
function validateCapFormat([headers, annotTypes]) {
  let issues = []
  if (!headers || !annotTypes) {
    return [['error', 'format:cap:no-cap-rows', 'File does not have 2 non-empty header rows']]
  }

  // Check format rules that apply to both metadata and cluster files
  issues = issues.concat(
    validateUnique(headers),
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

/** Verifies metadata file has all required columns */
function validateRequiredMetadataColumns(parsedHeaders) {
  const issues = []
  const firstLine = parsedHeaders[0]
  const missingCols = []
  REQUIRED_CONVENTION_COLUMNS.forEach(colName => {
    if (!firstLine.includes(colName)) {
      missingCols.push(colName)
    }
  })
  if (missingCols.length) {
    const msg = `File is missing required columns ${missingCols.join(', ')}`
    issues.push(['error', 'format:cap:metadata-missing-column', msg])
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
  if (fileOptions.use_metadata_convention) {
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
    // add other line-by-line validations here
    }
  })
  return { issues, delimiter, numColumns: headers[0].length }
}

/** parse a cluster file, and return an array of issues, along with file parsing info */
export async function parseClusterFile(chunker, mimeType) {
  const { headers, delimiter } = await getParsedHeaderLines(chunker, mimeType)
  let issues = validateCapFormat(headers)
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

/** confirm that the presence/absence of a .gz suffix matches the lead byte of the file
 * Throws an exception if the gzip is conflicted, since we don't want to parse further in that case
*/
export async function validateGzipEncoding(file, fileType) {
  // do not attempt to read AnnData files as this throws an error and prevents upload/sync
  if (fileType === 'AnnData') {
    return false
  }

  const GZIP_MAGIC_NUMBER = '\x1F'
  const fileName = file.name
  let isGzipped = null

  // read a single byte from the file to check the magic number
  const firstByte = await readFileBytes(file, 0, 1)
  if (fileName.endsWith('.gz') || fileName.endsWith('.bam')) {
    if (firstByte === GZIP_MAGIC_NUMBER) {
      isGzipped = true
    } else {
      throw new ParseException('encoding:invalid-gzip-magic-number',
        'File has a .gz or .bam suffix but does not seem to be gzipped')
    }
  } else {
    if (firstByte === GZIP_MAGIC_NUMBER) {
      throw new ParseException('encoding:missing-gz-extension',
        'File seems to be gzipped but does not have a ".gz" or ".bam" extension')
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
async function parseFile(file, fileType, fileOptions={}, sizeProps={}) {
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

  try {
    fileInfo.isGzipped = await validateGzipEncoding(file, fileType)
    // if the file is compressed or we can't figure out the compression, don't try to parse further
    const isFileFragment = file.size > sizeProps?.fileSizeTotal // likely a partial download from a GCP bucket
    if (
      !PARSEABLE_TYPES.includes(fileType) ||
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
      'MM Coordinate Matrix': parseSparseMatrixFile
    }

    if (parseFunctions[fileType]) {
      let ignoreLastLine = false
      if (sizeProps?.fetchedCompleteFile === false) {
        ignoreLastLine = true
        const msg =
          'Due to this file\'s size, it will be fully validated after sync, ' +
          'and any errors will be emailed to you.'

        parseResult.issues.push(['warn', 'incomplete:range-request', msg])
      }
      const chunker = new ChunkedLineReader(file, ignoreLastLine, fileInfo.isGzipped)

      const { issues, delimiter, numColumns } =
        await parseFunctions[fileType](chunker, fileInfo.fileMimeType, fileOptions)
      fileInfo.linesRead = chunker.linesRead
      fileInfo.delimiter = delimiter
      fileInfo.numColumns = numColumns
      parseResult.issues = parseResult.issues.concat(issues)

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
  }

  const perfTime = Math.round(performance.now() - startTime)

  const issues = parseResult.issues

  return {
    fileInfo,
    issues,
    perfTime
  }
}

export default function ValidateFileContent() {
  return ''
}

ValidateFileContent.parseFile = parseFile
