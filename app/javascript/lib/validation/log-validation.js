import { getSCPContext } from '~/providers/SCPContextProvider'
import { log } from '~/lib/metrics-api'

/** determine trigger for file-validation event (e.g. upload vs. sync) **/
function getValidationTrigger() {
  const pageName = getSCPContext().analyticsPageName
  if (pageName === 'studies-initialize-study') {
    return 'upload'
  } else if (pageName === 'studies-sync-study') {
    return 'sync'
  }
}

/** Trim messages and number of errors, to prevent Mixpanel 413 errors */
function getTrimmedIssueMessages(issues) {
  return issues.map(columns => {
    return columns[2].slice(0, 200) // Show <= 200 characters for each message
  }).slice(0, 20) // Show <= 20 messages
}

/** Get shared issue props for file-validation and study-validation */
export function getWarningAndErrorProps(errors, warnings) {
  const errorMessages = getTrimmedIssueMessages(errors)
  const warningMessages = getTrimmedIssueMessages(warnings)

  const errorTypes = Array.from(new Set(errors.map(columns => columns[1])))
  const warningTypes = Array.from(new Set(warnings.map(columns => columns[1])))

  return {
    errors: errorMessages,
    warnings: warningMessages,
    errorTypes, warningTypes,
    numErrors: errors.length,
    numWarnings: warnings.length,
    numErrorTypes: errorTypes.length,
    numWarningTypes: warningTypes.length
  }
}

/** Get properties about this validation run to log to Mixpanel */
export function getLogProps(fileInfo, issueObj, perfTimes) {
  const { errors, warnings, summary } = issueObj
  const trigger = getValidationTrigger()

  // Avoid needless gotchas in downstream analysis
  let friendlyDelimiter = 'tab'
  if (fileInfo.delimiter === ',') {
    friendlyDelimiter = 'comma'
  } else if (fileInfo.delimiter === ' ') {
    friendlyDelimiter = 'space'
  }

  const defaultProps = {
    ...fileInfo,
    ...perfTimes,
    trigger,
    'delimiter': friendlyDelimiter,
    'numTableCells': fileInfo.numColumns ? fileInfo.numColumns * fileInfo.linesRead : 0
  }

  if (errors.length === 0) {
    if (warnings.flat().includes('incomplete')) {
      return Object.assign({ status: 'incomplete' }, defaultProps)
    }
    return Object.assign({ status: 'success' }, defaultProps)
  } else {
    const issueProps = getWarningAndErrorProps(errors, warnings)

    const withIssueProps = Object.assign(defaultProps, issueProps)

    return Object.assign(withIssueProps, {
      status: 'failure',
      summary
    })
  }
}

/** Send analytics data to Mixpanel */
export function logFileValidation(fileInfo, issueObj, perfTimes) {
  const logProps = getLogProps(fileInfo, issueObj, perfTimes)
  log('file-validation', logProps)
}
