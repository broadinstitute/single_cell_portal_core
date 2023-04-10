/**
 * @fileoverview Functions for logging JS errors to Sentry
 *
 */
import * as Sentry from '@sentry/react'
import { BrowserTracing } from '@sentry/tracing'
import { getSCPContext } from '~/providers/SCPContextProvider'

/**
 * Log an exception to Sentry for bad response JS fetch executions
 * e.g. requests that result in a 404 response
 *
 * @param {Object} response - the response object from a failed JS fetch call
 * @param {String} titleInfo - extra info for the title of the Sentry event
 * @param {Boolean} useThrottle - whether to apply clientside rate limit throttling
 */
export function logJSFetchExceptionToSentry(response, titleInfo = '', useThrottle = false) {
  // add details from the response to the 'response info' object that will be logged in Sentry
  Sentry.setContext('response info', {
    status: response.status,
    statusText: response.statusText,
    url: response.url
  })

  const errorObj = new Error(`${response.status}: ${titleInfo}`)

  logToSentry(errorObj, useThrottle)
}

/**
 * Log an error to Sentry for failed JS fetch executions
 *
 * @param {Object} error - the error object from a failed JS fetch call
 * @param {String} titleInfo - extra info for the title of the Sentry event
 * @param {Boolean} useThrottle - whether to apply clientside rate limit throttling
 * @param {String} url - the url used in the fetch request that failed
 * @param {Object} init - the init object sent in the fetch request that failed

 */
export function logJSFetchErrorToSentry(error, titleInfo = '', useThrottle = false, url = '', init = {}) {
  // add details from the error to the 'error info' object that will be logged in Sentry
  Sentry.setContext('error info', {
    message: error.message,
    cause: error.cause,
    attemptedUrl: url,
    initObj: init
  })

  const errorObj = new Error(`${error}: ${titleInfo}`)
  logToSentry(errorObj, useThrottle)
}

/** Print suppression warning message to the console */
function printSuppression(errorObj, reason) {
  const reasonMap = {
    environment: 'in an unlogged environment',
    throttle: 'this event is throttled by client'
  }

  const message = `Suppressing error report to Sentry: ${reasonMap[reason]}`
  console.log(errorObj.url ? `${message }  Error:` : message)

  // Error objects are printed via console.error already, so only surface Sentry-suppressed responses
  if (errorObj.url) {
    console.log(errorObj)
  }
}

/** Determine if current environment should suppress logging to Sentry */
function getIsSuppressedEnv() {
  const env = getSCPContext().environment
  // Return `false` if manually locally testing Sentry logging
  return ['development', 'test'].includes(env)
}

/**
 * Log to Sentry, except if in unlogged environment or throttled away
 * @param {Object} error - Error object to log to Sentry
 * @param {Boolean} useThrottle - whether to apply clientside rate limit throttling. Default false.
 * @param {Number} sampleRate - % of events to log, only applied if `useThrottle = true`
 *  1 = log all events, 0 = log no events, default = 0.05 (i.e. log 5% of events)
 *
 * @return {Array} two-element array: [whether logging should occur, why if not]
 */
export function logToSentry(error, useThrottle = false, sampleRate = 0.05) {
  const isThrottled = useThrottle && Math.random() >= sampleRate

  if (getIsSuppressedEnv() || isThrottled) {
    const reason = isThrottled ? 'throttle' : 'environment'
    printSuppression(error, reason)
    return
  }

  Sentry.captureException(error)
}

/**
 *  Initialize Sentry to enable logging JS errors to Sentry
 */
export function setupSentry() {
  Sentry.init({
    dsn: 'https://a713dcf8bbce4a26aa1fe3bf19008d26@o54426.ingest.sentry.io/1424198',
    integrations: [new BrowserTracing()],

    // Sampling rate for transactions, which enrich Sentry events with traces
    tracesSampleRate: getIsSuppressedEnv() ? 0 : 1.0,
    beforeSend: event => {
      if (event.level === 'info') {
        return null
      }
      if (getIsSuppressedEnv()) {
        return null
      }

      return event
    }
  })

  // set the logger tag to reflect that the errors are from the frontend
  Sentry.setTag('logger', 'app-frontend')

  // set the scope for Sentry to the current environment
  Sentry.configureScope(scope =>
    scope.addEventProcessor(
      event =>
        new Promise(resolve =>
          resolve({
            ...event,
            environment: getSCPContext().environment
          })
        )
    )
  )
}
