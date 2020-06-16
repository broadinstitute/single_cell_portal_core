/**
 * @fileoverview Generic functions for usage analytics
 *
 * This module provides functions for tracking generic events (e.g. clicks),
 * as well as generic a logging function that integrates with Bard / Mixpanel.
 */

import { accessToken } from 'providers/UserProvider'

const defaultInit = {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'Content-Type': 'application/json'
  }
}

const bardDomainsByEnv = {
  development: 'https://terra-bard-dev.appspot.com',
  staging: 'https://terra-bard-alpha.appspot.com',
  production: 'https://terra-bard-prod.appspot.com'
}
let bardDomain = ''
let env = ''
let userId = ''

// TODO (SCP-2237): Use Node environment to get React execution context
if ('SCP' in window) {
  env = window.SCP.environment
  bardDomain = bardDomainsByEnv[env]
  // To consider: Replace SCP-specific userId with DSP-wide userId
  userId = window.SCP.userId
}

/**
 * Log page view, i.e. page load
 */
export function logPageView() {
  log('page:view')
}

/** Log click on page.  Delegates to more element-specific loggers. */
export function logClick(event) {
  // Don't log programmatically-triggered events,
  // e.g. trigger('click') via jQuery
  if (typeof event.isTrigger !== 'undefined') return

  const target = event.target
  const tag = target.localName.toLowerCase() // local tag name

  if (tag === 'a') {
    logClickLink(target)
  } else if (tag === 'button') {
    logClickButton(target)
  } else if (tag === 'input') {
    logClickInput(target)
  } else {
    // Perhaps uncomment when Mixpanel quota increases
    // logClickOther(target)
  }
}

/**
 * Log click on link, i.e. anchor (<a ...) tag
 */
function logClickLink(target) {
  const props = { text: target.text }
  log('click:link', props)
}

/**
 * Log click on button, e.g. for pagination, "Apply", etc.
 */
function logClickButton(target) {
  const props = { text: target.text }
  log('click:button', props)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga('send', 'event', 'click', 'button') // eslint-disable-line no-undef
}

/**
 * Get label elements for an input element
 *
 * From https://stackoverflow.com/a/15061155
 */
function getLabelsForInputElement(element) {
  let labels
  const id = element.id

  if (element.labels) {
    return element.labels
  }

  if (id) {
    labels = Array.from(document.querySelector(`label[for='${id}']`))
  }

  while (element = element.parentNode) {
    if (element.tagName.toLowerCase() == 'label') {
      labels.push(element)
    }
  }

  return labels
};

/**
 * Log click on input by type, e.g. text, number, checkbox
 */
function logClickInput(target) {
  const domLabels = getLabelsForInputElement(target)

  // User-facing label
  const label = domLabels.length > 0 ? domLabels[0].innerText : ''

  const props = { label }
  const element = `input-${target.type}`
  log(`click:${element}`, props)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga('send', 'event', 'click', element) // eslint-disable-line no-undef
}

/**
 * Log clicks on elements that are not otherwise classified
 */
function logClickOther(target) { // eslint-disable-line no-unused-vars
  const props = { text: target.text }
  log('click:other', props)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga('send', 'event', 'click', 'other') // eslint-disable-line no-undef
}

/**
 * Log front-end error (e.g. uncaught ReferenceError)
 */
export function logError(text) {
  const props = { text }
  log('error', props)
}

/**
 * Removes study name from URL, as it might have identifying information.
 * Terra UI omits workspace name in logs; this follows that precedent.
 *
 * For example, for a path like
 *    /single_cell/study/SCP123/private-study-with-sensitive-name
 *
 * This returns:
 *    /single_cell/study/SCP123
 *
 * @param {String} appPath Path name in URL
 */
function trimStudyName(appPath) {
  const studyOverviewMatch = appPath.match(/\/single_cell\/study\/SCP\d+/)
  if (studyOverviewMatch) {
    return studyOverviewMatch[0]
  } else {
    return appPath
  }
}

/**
 * Log metrics to Mixpanel via Bard web service
 *
 * Bard docs:
 * https://terra-bard-prod.appspot.com/docs/
 *
 * @param {String} name
 * @param {Object} props
 */
export function log(name, props={}) {
  const appPath = trimStudyName(window.location.pathname)

  props = Object.assign(props, {
    appId: 'single-cell-portal',
    timestamp: Date.now(),
    appPath,
    env
  })

  if ('SCP' in window && 'featuredSpace' in window.SCP) {
    // For e.g. COVID-19 featured space
    props['featuredSpace'] = window.SCP.featuredSpace
  }

  let init = Object.assign({}, defaultInit)

  if (accessToken === '') {
    // User is unauthenticated / unregistered / anonynmous
    props['distinct_id'] = userId
    delete init['headers']['Authorization']
  }

  const body = {
    body: JSON.stringify({
      event: name,
      properties: props
    })
  }

  init = Object.assign(init, body)

  if ('SCP' in window) { // Skips fetch during test
    fetch(`${bardDomain}/api/event`, init)
  }
}
