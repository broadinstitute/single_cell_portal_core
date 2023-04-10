/**
 * @fileoverview Generic functions for usage analytics
 *
 * This module provides functions for tracking generic events (e.g. clicks),
 * as well as generic a logging function that integrates with Bard / Mixpanel.
 */
import _find from 'lodash/find'
import _remove from 'lodash/remove'
import $ from 'jquery'
import { getDefaultProperties } from '@databiosphere/bard-client'
import { logJSFetchExceptionToSentry, logJSFetchErrorToSentry, logToSentry } from '~/lib/sentry-logging'

import { getAccessToken } from '~/providers/UserProvider'
import { getBrandingGroup } from '~/lib/scp-api'
import { getSCPContext } from '~/providers/SCPContextProvider'
import { setupWebVitalsLog, addPerfMetrics } from './metrics-perf'

let metricsApiMock = false

const defaultInit = {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${getAccessToken()}`,
    'Content-Type': 'application/json'
  }
}

const bardDomainsByEnv = {
  development: 'https://terra-bard-dev.appspot.com',
  staging: 'https://terra-bard-dev.appspot.com',
  production: 'https://terra-bard-prod.appspot.com'
}


// Disable ESLint for this assignment to ensure
// `pendingEvents` uses `let`, not `const`
let pendingEvents = [] // eslint-disable-line

let bardDomain = ''
const scpContext = getSCPContext()
const env = scpContext.environment
const devMode = scpContext.devMode
const version = scpContext.version
const isServiceWorkerCacheEnabled = scpContext.isServiceWorkerCacheEnabled
let userId = ''
let registeredForTerra = false

// TODO (SCP-2237): Use Node environment to get React execution context
if (env != 'test') {
  bardDomain = bardDomainsByEnv[env]
  // To consider: Replace SCP-specific userId with DSP-wide userId
  userId = window.SCP.userId
  registeredForTerra = window.SCP.registeredForTerra
}

/** Initializes any logging that  */
export function setupPageTransitionLog() {
  if (!metricsApiMock) {
    setupWebVitalsLog()
  }
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

  if (typeof event.isTrigger !== 'undefined') {return}


  const target = $(event.target)
  // don't double-log clicks we have otherwise instrumented
  const EXCLUDED_CLICK_SELECTOR = '.labeled-select'
  if (target.closest(EXCLUDED_CLICK_SELECTOR).length) {
    return
  }

  if (window.Appcues) {
    logAppcuesClicks()
  }

  // we use closest() so we don't lose clicks on, e.g. icons within a link/button
  // (and we have to use $.closest since IE still doesn't have built-in support for it)
  if (target.closest('a').length) {
    logClickLink(target.closest('a')[0])
  } else if (target.closest('button').length) {
    logClickButton(target.closest('button')[0])
  } else if (target.closest('input').length) {
    logClickInput(target.closest('input')[0])
  } else if (target.closest('.log-click').length > 0) {
    logClickOther(target.closest('.log-click')[0])
  }
}

/**
 * Logs Appcues public events to Mixpanel
 * https://docs.appcues.com/article/161-javascript-api
 *
 * Event prop building borrowed from Terra UI
 * https://github.com/DataBiosphere/terra-ui/pull/2463/files
 */
function logAppcuesClicks() {
  window.Appcues.on('all', (eventName, event) => {
    const eventProps = {
      'appcues.flowId': event.flowId,
      'appcues.flowName': event.flowName,
      'appcues.flowType': event.flowType,
      'appcues.flowVersion': event.flowVersion,
      'appcues.id': event.id,
      'appcues.interaction.category': event.interaction?.category,
      'appcues.interaction.destination': event.interaction?.destination,
      'appcues.interaction.element': event.interaction?.element,
      'appcues.interaction.fields': JSON.stringify(event.interaction?.fields),
      'appcues.interaction.formId': event.interaction?.formId,
      'appcues.interaction.text': event.interaction?.text, // not documented by Appcues, but observed and useful
      'appcues.interactionType': event.interactionType,
      'appcues.localeId': event.localeId,
      'appcues.localeName': event.localeName,
      'appcues.name': event.name,
      'appcues.sessionId': event.sessionId,
      'appcues.stepChildId': event.stepChildId,
      'appcues.stepChildNumber': event.stepChildNumber,
      'appcues.stepId': event.stepId,
      'appcues.stepNumber': event.stepNumber,
      'appcues.stepType': event.stepType,
      'appcues.timestamp': event.timestamp
    }
    log(eventName, eventProps)
    log('appcues:event', eventProps)
  })
}

/** Log clicks on SVG element of analytics interest */
export function logClickOther(target) {
  const props = {
    classList: getClassListAsArray(target),
    text: getNameForClickTarget(target)
  }
  log('click:other', props)
}

/** Log copy events, such as copying the SCP Zendesk support email */
export function logCopy(event) {
  const props = {
    text: getNameForClickTarget(event.target),
    classList: getClassListAsArray(event.target),
    id: event.target.id
  }
  log('copy', props)
}

/** Log contextmenu events, such right-click to "Save target as" or "Copy email address" */
export function logContextMenu(event) {
  const props = {
    text: getNameForClickTarget(event.target),
    classList: getClassListAsArray(event.target),
    id: event.target.id
  }
  log('contextmenu', props)
}

/**
  * If the element itself has a data-analytics-name, use that as the name
  * this allows names to be specified for elements that do not have text (e.g. icon buttons)
  */
function getNameForClickTarget(target) {
  let targetName = target.dataset.analyticsName
  if (!targetName && target.innerText) {
    // if there's no built-in analytics name just use the element text
    targetName = target.innerText.trim()
  }
  return targetName
}

/** Convert DOM classList to array, for easy exploration in Mixpanel */
function getClassListAsArray(target) {
  return 'classList' in target? Array.from(target.classList) : []
}

/** Check if a click is actually a tab click and update the props and event name as appropriate */
function getEventPropsWithTabsApplied(target, props, eventName) {
  // Check if target is a tab that's not a part of a menu
  const parentTabList = $(target).closest('[data-analytics-name][role="tablist"]')
  if (parentTabList.length > 0) {
    // Grab name of tab list and add to props
    props.tabListName = parentTabList[0].attributes['data-analytics-name'].value
    props.tabDisplayText = target.innerText.trim()
    // Update event as a tab click
    eventName = 'click:tab'
  }
  const updatedProps = props
  return { eventName, updatedProps }
}

/** Get text / name, classes, and ID for target element */
function getStandardClickProps(target) {
  return {
    text: getNameForClickTarget(target),
    classList: getClassListAsArray(target),
    id: target.id
  }
}

/**
 * Log click on link, i.e. anchor (<a ...) tag
 */
export function logClickLink(target) {
  const props = getStandardClickProps(target)
  // Check if target is a tab that's not a part of a menu
  const { eventName, updatedProps } = getEventPropsWithTabsApplied(target, props, 'click:link')
  log(eventName, updatedProps)
}

/**
 * Log click on button, e.g. for pagination, "Apply", etc.
 */
function logClickButton(target) {
  const props = getStandardClickProps(target)
  const { eventName, updatedProps } = getEventPropsWithTabsApplied(target, props, 'click:button')
  log(eventName, updatedProps)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga('send', 'event', 'click', 'button') // eslint-disable-line no-undef
}

/**
 * Get associated or nearest parent label text for an input element
 * returns empty string if none
 * From https://stackoverflow.com/a/15061155
 */
export function getLabelTextForElement(element, excludeElementText) {
  if (metricsApiMock === true) {return []} // Needed for metrics-api.test.js

  let label = null
  let labelText = ''

  if (element.labels && element.labels[0]) {
    label = element.labels[0]
  }
  if (!label) {
    const id = element.id
    if (id) {
      label = document.querySelector(`label[for='${id}']`)
    }
  }
  if (!label) { // traverse parents looking for label
    let parent = element
    while (parent = parent.parentNode) {
      if (parent.tagName?.toLowerCase() == 'label') {
        label = parent
        break
      }
    }
  }

  if (label) {
    // iterate over the label's children, getting their text, excluding the target element if specified
    let child = label.firstChild
    const texts = []
    while (child) {
      if (child.nodeType == 3) { // text node
        texts.push(child.data)
      } else if (child != element || !excludeElementText) {
        texts.push(child.innerText)
      }
      child = child.nextSibling
    }
    labelText = texts.join('').trim()
  }

  return labelText
};

/**
 * Log click on input by type, e.g. text, number, checkbox
 */
function logClickInput(target) {
  let props
  const label = getLabelTextForElement(target)
  if (target.type === 'radio') {
    const id = target.id
    const inputName = target.name
    const value = target.value

    props = { id, 'input-name': inputName, value, label }
  } else {
    props = { label }
    if (target.dataset.analyticsName) {
      props.text = target.dataset.analyticsName
    } else if (target.type === 'submit') {
      props.text = target.value
    }
  }
  const element = `input-${target.type}`
  log(`click:${element}`, props)
}

/** Log text of selected option when dropdown menu (i.e., select) changes */
export function logMenuChange(event) {
  // Get user-facing label
  const label = getLabelTextForElement(event.target)

  // Get newly-selected option
  const options = event.target.options
  const text = options[options.selectedIndex].text

  const props = { label, text }
  log('change:menu', props)
}

/**
 * Log JS error (e.g. uncaught ReferenceError) to console, Sentry, and Mixpanel
 */
export function logError(text, error = {}) {
  console.error(error.message)

  const props = { text, error }
  log('error', props) // Log to Mixpanel

  logToSentry(error)
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
 * gets the tab name for analytics
 */
function getTabProperty() {
  if (window.location.href?.match(/\?tab=/)) {
    return window.location.href.split('?tab=')[1]
  } else {
    return window.location.hash?.replace(/#/, '')
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
export function log(name, props = {}) {
  let isDifferentialExpressionEnabled // track differential expression visibility globally
  if ('isDifferentialExpressionEnabled' in props) {
    isDifferentialExpressionEnabled = props.isDifferentialExpressionEnabled
  } else {
    isDifferentialExpressionEnabled = !!window.SCP?.isDifferentialExpressionEnabled
  }

  // track A/B feature test assignments on all events
  const abTests = window.SCP?.abTests || []

  props = Object.assign(props, {
    appId: 'single-cell-portal',
    appPath: getAnalyticsPageName(),
    appFullPath: getAppFullPath(),
    env,
    logger: 'app-frontend',
    scpVersion: version,
    isDifferentialExpressionEnabled,
    isServiceWorkerCacheEnabled,
    abTests
  }, getDefaultProperties())

  const tab = getTabProperty()
  if (tab) {
    props['tab'] = tab
  }

  props['timeSincePageLoad'] = Math.round(performance.now())

  if (window.SCP && window.SCP.currentStudyAccession) {
    props['studyAccession'] = window.SCP.currentStudyAccession
  }

  checkForTriggeredPendingEvent(name, props)

  if ('SCP' in window && 'featuredSpace' in window.SCP) {
    // For e.g. COVID-19 featured space
    props['featuredSpace'] = window.SCP.featuredSpace
  }

  const brandingGroup = getBrandingGroup()
  props['brand'] = brandingGroup ? brandingGroup : ''
  props['registeredForTerra'] = registeredForTerra

  if ('perfTimes' in props) {
    try {
      props = addPerfMetrics(props)
    } catch (e) {
      console.error(e)
    }
    delete props.perfTimes
  }

  let init = Object.assign({}, defaultInit)

  if (getAccessToken() === '' || !registeredForTerra) {
    // User is unauthenticated, unregistered, anonymous,
    // or authenticated in SCP but not registered for Terra
    props['authenticated'] = (getAccessToken() !== '')
    props['distinct_id'] = userId
    delete init['headers']['Authorization']
  } else {
    props['authenticated'] = true
  }

  if (env === 'development') {
    // Log if developer is in Docker ("docker-compose").
    // Helps analyze factors of local SCP page speed.
    props['devMode'] = devMode
  }

  const body = {
    body: JSON.stringify({
      event: name,
      properties: props
    })
  }

  init = Object.assign(init, body)

  window.Appcues && window.Appcues.identify(window.SCP.userId)

  if ('SCP' in window || metricsApiMock) {
    const url = `${bardDomain}/api/event/`
    fetch(url, init).then(response => {
      // log failed attempts to connect with Bard to Sentry
      if (!response.ok) {
        logJSFetchExceptionToSentry(response, 'Error in fetch response when logging event to Bard', true)
      }
    // log errored attempts to connect with Bard to Sentry
    }).catch(error => {
      logJSFetchErrorToSentry(error, 'Error in JavaScript when logging event to Bard', true, url, init)
    })
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
  name, props = {}, completionTriggerPrefix, fromPageLoad
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
