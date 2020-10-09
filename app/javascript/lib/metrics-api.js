/**
 * @fileoverview Generic functions for usage analytics
 *
 * This module provides functions for tracking generic events (e.g. clicks),
 * as well as generic a logging function that integrates with Bard / Mixpanel.
 */

import { accessToken } from 'providers/UserProvider'
import { getBrandingGroup } from 'lib/scp-api'
import getSCPContext from 'providers/SCPContextProvider'
import { getDefaultProperties } from '@databiosphere/bard-client'
import _find from 'lodash/find'
import _remove from 'lodash/remove'
import $ from 'jquery'

let metricsApiMock = false

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

// Disable ESLint for this assignment to ensure
// `pendingEvents` uses `let`, not `const`
let pendingEvents = [] // eslint-disable-line

let bardDomain = ''
const env = getSCPContext().environment
let userId = ''
let registeredForTerra = false

// TODO (SCP-2237): Use Node environment to get React execution context
if (env != 'test') {
  bardDomain = bardDomainsByEnv[env]
  // To consider: Replace SCP-specific userId with DSP-wide userId
  userId = window.SCP.userId
  registeredForTerra = window.SCP.registeredForTerra
}

/**
 * Sets flag on whether to use mock data for Metrics API responses.
 *
 * This method is useful for tests and certain development scenarios,
 * e.g. when evolving a new API or to work around occasional API blockers.
 *
 * @param {Boolean} flag Whether to use mock data for all API responses
 */
export function setMetricsApiMockFlag(flag) {
  metricsApiMock = flag
}

/**
 * Log page view, i.e. page load
 */
export function logPageView() {
  log(`page:view:${getAnalyticsPageName()}`)
}

/** Log click on page.  Delegates to more element-specific loggers. */
export function logClick(event) {
  // Don't log programmatically-triggered events,
  // e.g. trigger('click') via jQuery

  if (typeof event.isTrigger !== 'undefined') return

  const target = $(event.target)
  // we use closest() so we don't lose clicks on, e.g. icons within a link/button
  // (and we have to use $.closest since IE still doesn't have built-in support for it)
  if (target.closest('a').length) {
    logClickLink(target.closest('a')[0])
  } else if (target.closest('button').length) {
    logClickButton(target.closest('button')[0])
  } else if (target.closest('input').length) {
    logClickInput(target.closest('input')[0])
  } else {
    // Perhaps uncomment when Mixpanel quota increases
    // logClickOther(target)
  }
}

function getNameForClickTarget(target) {
  let targetName = target.dataset.analyticsName
  if (!targetName) {
    // if there's no built-in analytics name just use the element text
    targetName = target.innerText.trim()
  }
  return targetName
}

/**
 * Log click on link, i.e. anchor (<a ...) tag
 */
export function logClickLink(target) {
  const props = {
    text: getNameForClickTarget(target),
    classList: 'classList' in target? Array.from(target.classList) : [],
    id: target.id
  }
  // Check if target is a tab that's not a part of a menu
  const parentTabList = $(target).closest('[data-analytics-name]')
  if (parentTabList.length > 0) {
    // Grab name of tab list and add to props
    props.tabListName = parentTabList[0].attributes['data-analytics-name'].value
    log('click:tab', props)
  } else {
    log('click:link', props)
  }
}

/**
 * Log click on button, e.g. for pagination, "Apply", etc.
 */
function logClickButton(target) {

  const props = { text: getNameForClickTarget(target) }
  log('click:button', props)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga('send', 'event', 'click', 'button') // eslint-disable-line no-undef
}

/**
 * Get label elements for an input element
 *
 * From https://stackoverflow.com/a/15061155
 */
function getLabelsForElement(element) {
  if (metricsApiMock === true) return [] // Needed for metrics-api.test.js

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
  const domLabels = getLabelsForElement(target)

  // User-facing label
  const label = domLabels.length > 0 ? domLabels[0].innerText : ''

  const props = { label }

  if (target.type === 'submit') {
    props.text = target.value
  }

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

/** Log text of selected option when dropdown menu (i.e., select) changes */
export function logMenuChange(event) {
  // Get user-facing label
  const domLabels = getLabelsForElement(event.target)
  const label = domLabels.length > 0 ? domLabels[0].innerText : ''

  // Get newly-selected option
  const options = event.target.options
  const text = options[options.selectedIndex].text

  const props = { label, text }
  log('change:menu', props)
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
 * gets the app path in a string suitable for logging
 * this includes the values of ids in the url
 * e.g. trims the study name out of window location
 */
function getAppFullPath() {
  return trimStudyName(window.location.pathname)
}

/**
 * gets the page name suitable for analytics
 * currently the rails controller + action name
 */
function getAnalyticsPageName() {
  return getSCPContext().analyticsPageName
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
  props = Object.assign(props, {
    appId: 'single-cell-portal',
    appPath: getAnalyticsPageName(),
    appFullPath: getAppFullPath(),
    env
  }, getDefaultProperties())

  checkForTriggeredPendingEvent(name, props)

  if ('SCP' in window && 'featuredSpace' in window.SCP) {
    // For e.g. COVID-19 featured space
    props['featuredSpace'] = window.SCP.featuredSpace
  }

  const brandingGroup = getBrandingGroup()
  props['brand'] = brandingGroup ? brandingGroup : ''
  props['registeredForTerra'] = registeredForTerra

  let init = Object.assign({}, defaultInit)

  props['timeSincePageLoad'] = Math.round(performance.now())

  if (accessToken === '' || !registeredForTerra) {
    // User is unauthenticated, unregistered, anonymous,
    // or authenticated in SCP but not registered for Terra
    props['authenticated'] = (accessToken !== '')
    props['distinct_id'] = userId
    delete init['headers']['Authorization']
  } else {
    props['authenticated'] = true
  }

  const body = {
    body: JSON.stringify({
      event: name,
      properties: props
    })
  }

  init = Object.assign(init, body)

  if ('SCP' in window || metricsApiMock) {
    // Skips fetch during test, unless explicitly testing Metrics API
    fetch(`${bardDomain}/api/event`, init)
  }
}

/**
 Initializes an event to log later (usually on completion of an async process)
 Handles measuring duration of the event.
 @param {String} name: the name of the event
 @param {} props: the props to pass along with the event.  This function
  automatically handles computing and adding 'perfTime' properties to the
  event props
 @param {String} completionTriggerPrefix: The prefix of an event on whose
  occurence this event should be automatically completed
  e.g. 'plot:' to complete the event automatically once a plot is finished
  rendering
 @param {Boolean} fromPageLoad: whether to use page view navigation -- instead
  of immediate trigger -- as start time.  Use if this pending event was
  triggered by a page load.

 @return {Object} Pending event, which has a complete() function for manually
  firing the log event
*/
export function startPendingEvent(
  name, props={}, completionTriggerPrefix, fromPageLoad
) {
  const startTime = fromPageLoad ? 0 : performance.now()
  const pendingEvent = {
    name,
    props,
    completionTriggerPrefix,
    startTime,
    complete: triggerEventProps => {
      const perfTime = performance.now() - startTime
      props.perfTime = Math.round(perfTime)
      if (triggerEventProps && triggerEventProps.perfTime) {
        // For now we just assume that triggered events always have a backend
        // and frontend component and naively measure the backend time as
        // (totalTime - frontendTime)
        const frontendTime = Math.round(triggerEventProps.perfTime)
        const backendTime = Math.round(props.perfTime - frontendTime)
        props['perfTime:frontend'] = frontendTime
        props['perfTime:backend'] = backendTime
      }
      log(name, props)
      _remove(pendingEvents, { name })
    }
  }
  pendingEvents.push(pendingEvent)
  return pendingEvent
}

/** Checks for events that are awaiting to be logged */
function checkForTriggeredPendingEvent(name, props) {
  const matchedPendingEvent = _find(pendingEvents, ce => {
    return name.startsWith(ce.completionTriggerPrefix)
  })
  if (matchedPendingEvent) {
    matchedPendingEvent.complete(props)
  }
}
