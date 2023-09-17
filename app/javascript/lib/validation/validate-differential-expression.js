import { getParsedHeaderLines } from './shared-validation'

/** Return a metric of differential expression size, if present in given metric */
function getSize(metric) {
  // Scanpy: logfoldchanges; Seurat: avg_log2FC
  const SIZE_REGEX = new RegExp(/(logfoldchange|log2FC|log2foldchange|lfc)/i)
  const size = metric.match(SIZE_REGEX)
  return size
}

// Start of significance parsers

/** Get "adjusted p-value"-like metric */
function getPvalAdj(metric) {
  // Scanpy: pvals_adj; Seurat: p_val_adj; edgeR: FDR
  const ADJUSTED_P_VALUE_REGEX = new RegExp(/(pvals_adj|p_val_adj|adj|fdr)/i)
  const pvalAdj = metric.match(ADJUSTED_P_VALUE_REGEX)
  return pvalAdj
}

/** Return a "p-value"-like string if present in given metric , excluding "adjusted p-value"-like */
function getPval(metric) {
  // Conventions -- Scanpy: pvals; Seurat: p_val
  const P_VALUE_REGEX = new RegExp(/(pval|p_val|p-val)/i)
  const pval = metric.match(P_VALUE_REGEX)
  const pvalAdj = getPvalAdj(metric)
  if (!pvalAdj) {
    return pval
  }
}

/** Return a "q-value"-like string if present in given metric */
function getQval(metric) {
  // Conventions -- Scanpy: qvals (?); Seurat: q_val (?)
  const Q_VALUE_REGEX = new RegExp(/(qval|q_val|q-val)/i)
  const qval = metric.match(Q_VALUE_REGEX)
  return qval
}

/** Get a significance-centric sort key for the metric */
function getSigKey(metric) {
  const pvalAdj = getPvalAdj(metric)
  if (pvalAdj) {
    // Rank "adjusted p-value" 1st
    return 0
  } else {
    // Rank "q-value" 2nd
    const qval = getQval(metric)
    if (qval) {
      return 1
    } else {
      // Rank "p-value" 3nd
      const pval = getPval(metric)
      if (pval) {
        return 2
      } else {
        // Rank everything else lower
        return 3
      }
    }
  }
}

/** Return a significance string if present in given metric */
function getSignificance(metric) {
  const pvalAdj = getPvalAdj(metric)
  if (pvalAdj) {
    return pvalAdj
  } else {
    const pval = getPval(metric)
    if (pval) {
      return pval
    } else {
      const qval = getQval(metric)
      if (qval) {
        return qval
      } else {
        return null
      }
    }
  }
}
// End of significance parsers


/** Return actual size and significance header, if present in given metrics */
function inferSizesAndSignificances(metrics) {
  const sizes = metrics.filter(metric => getSize(metric))
  const rawSignificances = metrics.filter(metric => getSignificance(metric))
  const significances = rawSignificances.sort((a, b) => getSigKey(a) - getSigKey(b))

  return [sizes, significances]
}


/** Return a metric of differential expression size, if present in given metric */
function getGeneHeader(header) {
  // Conventions -- Scanpy: names; Seurat: genes.  "gene" is SCP canonical.
  const GENE_REGEX = new RegExp(/^(gene|genes|names)$/i)
  const gene = header.match(GENE_REGEX)
  return gene
}

/**
 * Return 'comparison_group', if present.
 *
 * (We haven't seen any variants of this required header; we can refine this
 * check if/when we encounter them in concrete examples.)
 */
function getComparisonGroupHeader(header) {
  if (header === 'comparison_group') {
    return header
  }
}

/** Return a metric of differential expression size, if present in given metric */
function getGroupHeader(header) {
  // Conventions -- Scanpy: ?; Seurat: cluster.  "group" is SCP canonical.
  const GROUP_REGEX = new RegExp(/(group|cluster)/i)
  const group = header.match(GROUP_REGEX)
  const comparisonGroup = getComparisonGroupHeader(header)
  if (!comparisonGroup) {
    return group
  }
}

/** Return actual size and significance header, if present in given metrics */
function inferOtherHeaders(headers) {
  const geneHeaders = headers.filter(header => getGeneHeader(header))
  const groupHeaders = headers.filter(header => getGroupHeader(header))
  const comparisonGroupHeaders = headers.filter(header => getComparisonGroupHeader(header))

  return [geneHeaders, groupHeaders, comparisonGroupHeaders]
}

/** Validates "gene", "group", and (if applicable) "comparison group" headers */
function validateOtherHeaders(headers) {
  const issues = []
  const [geneHeaders, groupHeaders, comparisonGroupHeaders] = inferOtherHeaders(headers)
  const hasGeneHeaders = geneHeaders.length > 0
  const hasGroupHeaders = groupHeaders.length > 0
  // const hasComparisonGroupHeaders = comparisonGroupHeaders.length > 1

  if (!hasGeneHeaders || !hasGroupHeaders) {
    let warningType = 'format:cap:'
    const inHeaders = `in headers: ${headers}`
    const instruction = 'Column headers must include headers for genes and groups.'
    let issue = instruction
    let missing
    let menus
    if (!hasGeneHeaders && !hasGroupHeaders) {
      issue += '  No "gene" or "group" headers found'
      missing = 'headers for gene and group'
      warningType += 'no-gene-or-group'
      menus = '"Gene header" and "Group header" menus'
    } else if (!hasGeneHeaders) {
      issue += '  No "gene" header found'
      missing = 'a header for genes'
      warningType += 'no-gene'
      menus = '"Gene header" menu'
    } else if (!hasGroupHeaders) {
      issue += '  No "group" header found'
      missing = 'a "group" header'
      warningType += 'no-group'
      menus = '"Group header" menu'
    }
    issue += (
      ` ${inHeaders}.  Please update your file to add ${missing}, ` +
      `or select from "Other options" in the ${menus} below.`
    )
    issues.push(['warn', warningType, issue])
  }

  return [issues, geneHeaders, groupHeaders, comparisonGroupHeaders]
}

/**
 * Report whether size and/or significance are detected among metrics
 *
 * TODO:
 *  - Update or clear warning if user selects from "Other options" for a metric
 */
function validateSizeAndSignificance(metrics) {
  const issues = []
  const [sizes, significances] = inferSizesAndSignificances(metrics)
  const hasSize = sizes.length > 0
  const hasSignificance = significances.length > 0
  if (!hasSize || !hasSignificance) {
    let warningType = 'format:cap:'
    const inHeaders = `in headers: ${metrics}`
    const instruction = 'Column headers must include a size and significance metric.'
    let issue = instruction
    let missing
    let menus
    if (!hasSize && !hasSignificance) {
      issue += '  No size or significance metrics found'
      missing = 'headers with metrics for size and significance'
      warningType += 'no-size-or-significance'
      menus = '"Size metric" and "Significance metric" menus'
    } else if (!hasSize) {
      issue += '  No size metric found'
      missing = 'a header with a metric for size'
      warningType += 'no-size'
      menus = '"Size metric" menu'
    } else if (!hasSignificance) {
      issue += '  No significance metric found'
      missing = 'a header with a metric for significance'
      warningType += 'no-significance'
      menus = '"Significance metric" menu'
    }
    issue += (
      ` ${inHeaders}.  Please update your file to add ${missing}, ` +
      `or select from "Other options" in the ${menus} below.`
    )
    issues.push(['warn', warningType, issue])
  }

  return [issues, sizes, significances]
}

/**
 * Determine from headers whether DE file has "long" or "wide" format
 *
 * Notes:
 * - Long format 1st headers e.g. ['genes', 'logfoldchanges']
 * - Wide format 1st headers e.g. ['genes', 'A--rest--logfoldchanges']
 * - Long format is default / likely more common
 */
function parseDeFileFormat(headers) {
  const firstLineHeaders = headers[0]
  const deFileFormat = !firstLineHeaders[1].includes('--') ? 'long' : 'wide'
  return deFileFormat
}

/**
 * Return metrics from headers of file; especially helpful for "wide" format
*/
function parseMetricsAndDeHeaders(headers, format) {
  const firstLineHeaders = headers[0]
  const metricHeaders = firstLineHeaders.filter(
    header => !['gene', 'genes', 'group', 'cluster', 'comparison_group'].includes(header)
  )

  if (format === 'long') {
    return [metricHeaders, firstLineHeaders]
  }

  // Get a de-duplicated list of metrics from wide-format headers.
  // First, get an initial array of metrics, which will contain many duplicates
  const dupMetrics = metricHeaders.map(header => header.split('--').slice(-1)[0])
  const metrics = [...new Set(dupMetrics)] // Then, uniquify that array
  return [metrics, firstLineHeaders]
}

/** Parse DE file, and return an array of issues, along with file parsing info */
export async function parseDifferentialExpressionFile(chunker, mimeType) {
  const { headers, delimiter } = await getParsedHeaderLines(chunker, mimeType)

  let issues = []

  // Validate header-content
  const deFileFormat = parseDeFileFormat(headers)
  const [metrics, deHeaders] = parseMetricsAndDeHeaders(headers, deFileFormat)
  const [metricsIssues, sizes, significances] = validateSizeAndSignificance(metrics)
  issues = issues.concat(metricsIssues)
  const [
    otherHeadersIssues, geneHeaders, groupHeaders, comparisonGroupHeaders
  ] = validateOtherHeaders(headers[0])
  issues = issues.concat(otherHeadersIssues)

  console.log('deHeaders', deHeaders)
  const notes = {
    metrics, deHeaders, deFileFormat,
    geneHeaders, groupHeaders, comparisonGroupHeaders,
    sizes, significances
  }

  // Add any future body-content validations like so:
  //
  // const dataObj = {} // object to track multi-line validation concerns
  // await chunker.iterateLines({
  //   func: (rawLine, lineNum, isLastLine) => {
  //     issues = issues.concat(timeOutCSFV(chunker))

  //     const line = parseLine(rawLine, delimiter)
  //     issues = issues.concat(validateUniqueCellNamesWithinFile(line, isLastLine, dataObj))
  //     issues = issues.concat(validateGroupColumnCounts(headers, line, isLastLine, dataObj))
  //   // add other line-by-line validations here
  //   }
  // })

  return { issues, delimiter, numColumns: headers[0].length, notes }
}
