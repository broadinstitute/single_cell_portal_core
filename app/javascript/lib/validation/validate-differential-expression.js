import {
  getParsedHeaderLines, parseLine,
  validateUniqueCellNamesWithinFile, validateGroupColumnCounts, timeOutCSFV
} from './shared-validation'

function getSize(metric) {
  // Scanpy: logfoldchanges; Seurat: avg_log2FC
  const SIZE_REGEX = new RegExp(/(logfoldchange|log2FC|log2foldchange|lfc)/i)
  const size = metric.match(SIZE_REGEX)
  return size
}

// Significance parsers ###
// TODO (SCP-): Custom tooltips for custom metrics
/** Get "adjusted p-value"-like metric */
function getPvalAdj(metric) {
  // Scanpy: pvals_adj; Seurat: p_val_adj
  const ADJUSTED_P_VALUE_REGEX = new RegExp(/(pvals_adj|p_val_adj|adj)/i)
  const pvalAdj = metric.match(ADJUSTED_P_VALUE_REGEX)
  return pvalAdj
}

/** Return a "p-value"-like string if present in given metric , excluding "adjusted p-value"-like */
function getPval(metric) {
  // Scanpy: pvals; Seurat: p_val
  const P_VALUE_REGEX = new RegExp(/(pval|p_val|p-val)/i)
  const pval = metric.match(P_VALUE_REGEX)
  const pvalAdj = getPvalAdj(metric)
  if (!pvalAdj) {
    return pval
  }
}

/** Return a "q-value"-like string if present in given metric */
function getQval(metric) {
  // Scanpy: qvals (?); Seurat: q_val (?)
  const Q_VALUE_REGEX = new RegExp(/(qval|q_val|q-val)/i)
  const qval = metric.match(Q_VALUE_REGEX)
  return qval
}

/** Get a significance-centric sort key for the metric */
function getSigKey(metric) {
  const pvalAdj = getPvalAdj(metric)
  if (pvalAdj) {
    // Rank adjusted p-value 1st
    return 0
  } else {
    // Rank q-value 2nd
    const qval = getQval(metric)
    if (qval) {
      return 1
    } else {
      // Rank p-value 3nd
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
  console.log('ok 4')
  const pvalAdj = getPvalAdj(metric)
  console.log('ok 5')
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
        console.log('metric', metric)
        return null
      }
    }
  }
}
// // End significance parsers


/** Return size and significance values, if present in given metrics */
function getSizesAndSignificances(metrics) {
  const sizes = metrics.filter(metric => getSize(metric))
  const rawSignificances = metrics.filter(metric => getSignificance(metric))
  const significances = rawSignificances.sort((a, b) => getSigKey(a) - getSigKey(b))

  return [sizes, significances]
}


/**
 * Report whether size and/or significance are detected among metrics
 *
 * TODO:
 *  - When UI is more robust, convert to logger.warn and don't throw errors
 *  - Log to Sentry / Mixpanel
 */
function validateSizeAndSignificance(metrics) {
  const issues = []
  let issue
  console.log('ok')
  const [sizes, significances] = getSizesAndSignificances(metrics)
  const hasSize = sizes.length > 0
  const hasSignificance = significances.length > 0
  console.log('*** sizes, significances', sizes, significances)
  const inHeaders = `in headers: ${metrics}`
  const instruction = 'Column headers must include "logfoldchanges" and "qval".'
  if (!hasSize && !hasSignificance) {
    issue = `${instruction}  No size or significance metrics found ${inHeaders}`
  } else if (!hasSize) {
    issue = `${instruction}  No size metrics found ${inHeaders}`
  } else if (!hasSignificance) {
    issue = `${instruction}  No significance metrics found ${inHeaders}`
  }

  if (issue) {
    issues.push(['error', issue])
  }

  return [issues, sizes, significances]
}

/** Parse DE file, and return an array of issues, along with file parsing info */
export async function parseDifferentialExpressionFile(chunker, mimeType) {
  const { headers, delimiter } = await getParsedHeaderLines(chunker, mimeType)
  console.log('headers[0]', headers[0])
  const metrics = headers[0].filter(
    header => !['gene', 'genes', 'group', 'comparison_group'].includes(header)
  )
  const [issues, sizes, significances] = validateSizeAndSignificance(metrics)
  console.log('sizes, significances', sizes, significances)
  const notes = { sizes, significances, metrics }

  // add other header validations here

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
