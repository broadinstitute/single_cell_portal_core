/**
* @fileoverview Functions used in multiple file types validation
*/

// Ultimately sourced from: scp-ingest-pipeline/schemas
import * as _schema from 'lib/assets/metadata_schemas/alexandria_convention/alexandria_convention_schema.json';

export const metadataSchema = _schema
export const REQUIRED_CONVENTION_COLUMNS = metadataSchema.required.filter(c => c !== 'CellID')

/**
 * ParseException can be thrown when we encounter an error that prevents us from parsing the file further
 */
export function ParseException(key, msg) {
  this.message = msg
  this.key = key
}

/**
 * reads in a two lines to be used as header lines, sniffs the delimiter,
 * and returns the lines parsed by the sniffed delimiter
 */
export async function getParsedHeaderLines(chunker, mimeType) {
  const headerLines = []
  await chunker.iterateLines({
    func: (line, lineNum, isLastLine) => {
      headerLines.push(line)
    }, maxLines: 2
  })
  if (headerLines.length < 2 || headerLines.some(hl => hl.length === 0)) {
    throw new ParseException('format:cap:missing-header-lines',
      `Your file is missing newlines or some required header lines`)
  }
  const delimiter = sniffDelimiter(headerLines, mimeType)
  const headers = headerLines.map(l => parseLine(l, delimiter))
  return { headers, delimiter }
}

/**
 * Guess whether column delimiter is comma or tab
 *
 * Consider using `papaparse` NPM package once it supports ES modules.
 * Upstream task: https://github.com/mholt/PapaParse/pull/875
 */
function sniffDelimiter([line1, line2], mimeType) {
  const delimiters = [',', '\t']
  let bestDelimiter

  delimiters.forEach(delimiter => {
    const numFieldsLine1 = line1.split(delimiter).length
    const numFieldsLine2 = line2.split(delimiter).length

    if (numFieldsLine1 !== 1 && numFieldsLine1 === numFieldsLine2) {
      bestDelimiter = delimiter
    }
  })

  if (typeof bestDelimiter === 'undefined') {
    if (mimeType === 'text/tab-separated-values') {
      bestDelimiter = '\t'
    } else {
      // fall back on comma -- which may give the most useful error message to the user
      bestDelimiter = ','
    }
  }
  return bestDelimiter
}

/**
 * Splits the line on a delimiter, and
 * removes leading and trailing white spaces and quotes from values
 */
export function parseLine(line, delimiter) {
  const splitLine = line.split(delimiter)
  const parsedLine = new Array(parseLine.length)
  for (let i = 0; i < splitLine.length; i++) {
    parsedLine[i] = splitLine[i].trim().replaceAll(/^"|"$/g, '')
  }
  return parsedLine
}

/**
 * Verify cell names are each unique for a file
 * creates and uses 'cellNames' and 'duplicateCellNames' properties on dataObj to track
 * cell names between calls to this function
 */
export function validateUniqueCellNamesWithinFile(line, isLastLine, dataObj) {
  const issues = []

  dataObj.cellNames = dataObj.cellNames ? dataObj.cellNames : new Set()
  dataObj.duplicateCellNames = dataObj.duplicateCellNames ? dataObj.duplicateCellNames : new Set()
  const cell = line[0]

  if (!dataObj.cellNames.has(cell)) {
    dataObj.cellNames.add(cell)
  } else {
    dataObj.duplicateCellNames.add(cell)
  }
  if (isLastLine && dataObj.duplicateCellNames.size > 0) {
    const nameTxt = (dataObj.duplicateCellNames.size > 1) ? 'duplicates' : 'duplicate'
    const dupString = [...dataObj.duplicateCellNames].slice(0, 10).join(', ')
    const msg =
      'Cell names must be unique within a file. ' +
      `${dataObj.duplicateCellNames.size} ${nameTxt} found, including: ${dupString}`
    issues.push(['error', 'content:duplicate:cells-within-file', msg])
  }
  return issues
}


/**
 * Verify that, for id columns with a corresponding label column, no label is
 * shared across two or more ids.  The main circumstance this is aimed at
 * checking is the 'Excel drag error', in which by drag-copying a row, the
 * label is copied correctly, but the id string gets numerically incremented.
 */
export function validateMetadataLabelMatches(headers, line, isLastLine, dataObj) {
  const issues = []
  const excludedColumns = ['NAME']
  // if this is the first time through, identify the columns to check, and
  // initialize data structures to track mismatches
  if (!dataObj.dragCheckColumns) {
    dataObj.dragCheckColumns = headers[0].map((colName, index) => {
      const labelColumnIndex = headers[0].indexOf(`${colName}__ontology_label`)
      if (excludedColumns.includes(colName) ||
        colName.endsWith('ontology_label') ||
        headers[1][index] === 'numeric' ||
        labelColumnIndex === -1) {
        return null
      }
      // for each column, track a hash of label=>value,
      // and also a set of mismatched values--where the same label is used for different ids
      return { colName, index, labelColumnIndex, labelValueMap: {}, mismatchedVals: new Set() }
    }).filter(c => c)
  }
  // for each column we need to check, see if there is a corresponding filled-in label,
  //  and track whether other ids have been assigned to that label too
  for (let i = 0; i < dataObj.dragCheckColumns.length; i++) {
    const dcc = dataObj.dragCheckColumns[i]
    const colValue = line[dcc.index]
    const label = line[dcc.labelColumnIndex]
    if (label.length) {
      if (dcc.labelValueMap[label] && dcc.labelValueMap[label] !== colValue) {
        dcc.mismatchedVals.add(label)
      } else {
        dcc.labelValueMap[label] = colValue
      }
    }
  }
  // only report out errors if this is the last line of the file so that a
  // single, consolidated message can be displayed per column
  if (isLastLine) {
    dataObj.dragCheckColumns.forEach(dcc => {
      if (dcc.mismatchedVals.size > 0) {
        const labelString = [...dcc.mismatchedVals].slice(0, 10).join(', ')
        const moreLabelsString = dcc.mismatchedVals.size > 10 ? ` and ${dcc.mismatchedVals.size - 10} others` : ''
        issues.push(['error', 'ontology:multiply-assigned-label',
          `${dcc.colName} has different ID values mapped to the same label.
          Label(s) with more than one corresponding ID: ${labelString}${moreLabelsString}`])
      }
    })
  }
  return issues
}


/**
 * For cluster and metadata files raises a warning if a group column has more than 200 unique values
 * */
export function validateGroupColumnCounts(headers, line, isLastLine, dataObj) {
  const issues = []
  const excludedColumns = ['NAME']
  if (!dataObj.groupCheckColumns) {
    dataObj.groupCheckColumns = headers[0].map((colName, index) => {
      if (excludedColumns.includes(colName) || colName.endsWith('ontology_label') || headers[1][index] === 'numeric') {
        return null
      }
      return { colName, index, uniqueVals: new Set() }
    }).filter(c => c)
  }
  for (let i = 0; i < dataObj.groupCheckColumns.length; i++) {
    const gcc = dataObj.groupCheckColumns[i]
    const colValue = line[gcc.index]
    if (colValue) { // don't bother adding empty values
      gcc.uniqueVals.add(colValue)
    }
  }

  if (isLastLine) {
    dataObj.groupCheckColumns.forEach(gcc => {
      if (gcc.uniqueVals.size > 200) {
        issues.push([
          'warn', 'content:group-col-over-200',
          `${gcc.colName} has over 200 unique values and so will not be visible in plots -- is this intended?`
        ])
      }
    })
  }
  return issues
}

/**
 * Verify headers are unique and not empty
 */
export function validateUnique(headers) {
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
 * Check headers for disallowed characters in metadata annotations
 *
 * This rule exists because BigQuery does not except e.g. periods in its
 * column names, without special quoting.  We use BigQuery to enable cross-study
 * search on annotations like "species", "disease", etc.
 *
 * Cluster-specific annotations aren't searchable in cross-study search, so
 * we skip this rule for cluster files (via `false` for `hasMetadataAnnotations`).
 *
 * More context: https://github.com/broadinstitute/single_cell_portal_core/pull/2143
 */
export function validateAlphanumericAndUnderscores(headers, hasMetadataAnnotations=true) {
  // eslint-disable-next-line max-len
  // Mirrors https://github.com/broadinstitute/scp-ingest-pipeline/blob/7c3ea039683c3df90d6e32f23bf5e6813d8fbaba/ingest/validation/validate_metadata.py#L1223
  const issues = []

  if (!hasMetadataAnnotations) {
    // Skip this validation for cluster files
    return issues
  }


  const uniques = new Set(headers)
  const prohibitedChars = new RegExp(/[^A-Za-z0-9_]/)

  const problemHeaders = []

  // Do headers have prohibited characters?
  uniques.forEach(header => {
    const hasProhibited = (header.search(prohibitedChars) !== -1)
    if (hasProhibited) {
      problemHeaders.push(header)
    }
  })

  if (problemHeaders.length > 0) {
    const problems = `"${problemHeaders.join('", "')}"`
    const msg = `Update these headers to use only letters, numbers, and underscores: ${problems}`
    issues.push(['error', 'format:cap:only-alphanumeric-underscore', msg])
  }

  return issues
}

/** Verifies metadata file has all required columns */
export function validateRequiredMetadataColumns(parsedHeaders, isAnnData=false) {
  const issues = []
  const firstLine = parsedHeaders[0]
  const missingCols = []
  REQUIRED_CONVENTION_COLUMNS.forEach(colName => {
    if (!firstLine.includes(colName)) {
      missingCols.push(colName)
    }
  })
  if (missingCols.length) {
    const columns = isAnnData ? 'obs keys' : 'columns'
    const msg = `File is missing required ${columns}: ${missingCols.join(', ')}`
    issues.push(['error', 'format:cap:metadata-missing-column', msg])
  }

  return issues
}

/**
 * Timeout the CSFV if taking longer than 10 seconds
 *
 */
export function timeOutCSFV(chunker) {
  const maxTime = 10000 // in milliseconds this equates to 10 seconds
  const maxRealTime = chunker.startTime + maxTime
  const currentTime = Date.now()
  const issues = []

  if (currentTime > maxRealTime) {
    // quit early by setting the file reader to the end of the file so it can't read anymore
    chunker.setToFileEnd()
    issues.push(['warn', 'incomplete:timeout',
      'Due to this file\'s size, it will be fully validated after upload, and any errors will be emailed to you.'])
  }
  return issues
}
