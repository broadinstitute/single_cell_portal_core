import React from 'react'
import ReactDOM from 'react-dom'
import morpheus from 'morpheus-app'
import { Spinner } from 'spin.js'

import '~/styles/application.scss'
import HomePageContent from '~/components/HomePageContent'
import ExploreView from '~/components/explore/ExploreView'
import { AuthorEmailPopup } from '~/lib/InfoPopup'
import UploadWizard from '~/components/upload/UploadWizard'
import MyStudiesPage from '~/components/my-studies/MyStudiesPage'
import StudyUsageInfo from '~/components/my-studies/StudyUsageInfo'
import ValidationMessage from '~/components/validation/ValidationMessage'
import ClusterAssociationSelect from '~/components/upload/ClusterAssociationSelect'
import RawAssociationSelect from '~/components/upload/RawAssociationSelect'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import checkMissingAuthToken from '~/lib/user-auth-tokens'
import ValidateFile from '~/lib/validation/validate-file'
import { setupSentry } from '~/lib/sentry-logging'
import { clearOldServiceWorkerCaches } from '~/lib/service-worker-cache'

const { validateRemoteFile } = ValidateFile

import {
  logPageView, logClick, logMenuChange, setupPageTransitionLog, log, logCopy, logContextMenu
} from '~/lib/metrics-api'
import * as ScpApi from '~/lib/scp-api'

window.SCP = window.SCP ? window.SCP : {}

// Set up the context for Sentry to log front-end errors
setupSentry()

// On each page load, check for old SCP caches, delete any found
clearOldServiceWorkerCaches()

document.addEventListener('DOMContentLoaded', () => {
  // Logs only page views for faceted search UI
  logPageView()

  $(document).on('click', 'body', logClick)
  $(document).on('change', 'select', logMenuChange)
  $(document).on('copy', 'body', logCopy)
  // contextmenu event is to handle when users use context menu "copy email address" instead of cmd+C copy event as
  // this does not emit the copy event
  $(document).on('contextmenu', 'body', logContextMenu)

  setupPageTransitionLog()

  if (window.SCP.readOnlyToken && window.SCP.studyAccession) {
    ScpApi.setupRenewalForReadOnlyToken(window.SCP.studyAccession)
  }

  const path = window.location.pathname
  const onTosPage = path.includes('terra_tos') || path.includes('accept_tos')
  if (!onTosPage && window.SCP.userSignedIn) {
    ScpApi.checkTerraTosAcceptance().then(mustAcceptTerraTos => {
      if (mustAcceptTerraTos) {
        window.location = '/single_cell/terra_tos'
      }
    })
  }

  setTimeout(checkMissingAuthToken, 1000);
})

const componentsToExport = {
  HomePageContent, ExploreView, UploadWizard, ValidationMessage, ClusterAssociationSelect,
  RawAssociationSelect, AuthorEmailPopup, MyStudiesPage, StudyUsageInfo
}

/** helper to render React components from non-react portions of the app
 * @param {String|Element} target - the html element to render on, can be either an element or an id
 * @param {String} componentName - the component to render -- must be included in the `componentsToExport` above
 * @param {Object} props - the props to pass to the component
*/
function renderComponent(target, componentName, props) {
  let targetEl = target
  if (typeof target === 'string' || target instanceof String) {
    targetEl = document.getElementById(target)
  }
  ReactDOM.unmountComponentAtNode(targetEl)
  ReactDOM.render(React.createElement(componentsToExport[componentName], props),
    targetEl)
}

// SCP expects these variables to be global.
//
// If adding a new variable here, also add it to .eslintrc.js

/** put the function globally accessible, replacing the pre-registration 'renderComponent'
 * setup in assets/application.js */
window.SCP.renderComponent = renderComponent
/** render any components that were registered to render prior to this script loading */
window.SCP.componentsToRender.forEach(componentToRender => {
  renderComponent(componentToRender.target, componentToRender.componentName, componentToRender.props)
})

/** assing the global log function, and log any events that were queued */
window.SCP.log = log
window.SCP.eventsToLog.forEach(eventToLog => {
  log(eventToLog.name, eventToLog.props)
})

window.SCP.getFeatureFlagsWithDefaults = getFeatureFlagsWithDefaults
window.SCP.validateRemoteFile = validateRemoteFile
window.SCP.API = ScpApi

window.Spinner = Spinner
window.morpheus = morpheus
