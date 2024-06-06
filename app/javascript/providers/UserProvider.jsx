import React, { useState } from 'react'

import { updateCurrentUser } from '~/lib/scp-api'


/**
  * Returns the current access token for the user
  * window.SCP is not available when running via Jest tests,
  * so default such cases to a string "test"
  */
export function getAccessToken() {
  return ('SCP' in window && !window.SCP.isTest) ? window.SCP.userAccessToken : 'test'
}

/**
 * Returns the current read-only access token for the user
 * This token is specifically for genome visualizations like IGV and Ideogram
 * as they both require streaming a GCS object directly to the client
 * This token needs the devstorage.read_only OAuth scope, which is returned
 * from ApplicationHelper#get_read_access_token and stored in the window.SCP object
 */
export function getReadOnlyToken() {
  return ('SCP' in window) ? window.SCP.readOnlyToken : 'test'
}

/** returns true if the current user is logged in */
export function isUserLoggedIn() {
  return !!getAccessToken()
}

/** Returns true if user is registered for Terra */
export function isUserRegisteredForTerra() {
  return ('SCP' in window) ? window.SCP.registeredForTerra : 'test'
}

/**
 * returns true if the signed-in user has completed their Terra profile by
 * checking if a pet service account token has been issued via getReadOnlyToken
 */
export function userHasTerraProfile() {
  return !!isUserLoggedIn() && !!getReadOnlyToken()
}

/**
  * Returns a scope-limited access token that can be used as a URL param
  * window.SCP is not available when running via Jest tests,
  * so default such cases to a string "test"
  */
export function getURLSafeAccessToken() {
  return ('SCP' in window) ? window.SCP.URLSafeAccessToken : 'test'
}

/** Returns the feature flags with defaults for the current user */
export function getFeatureFlagsWithDefaults() {
  const flags = readUserInfoFromPage().featureFlagsWithDefaults
  flags.show_igv_multiome = true
  return flags
}

/** for now, read it off the home page.  Eventually, this will want to be an API call */
function readUserInfoFromPage() {
  let userInfo = {}
  const userElement = document.getElementById('user-provider-info')
  if (userElement) {
    userInfo = JSON.parse(userElement.value)
  }
  return userInfo
}

const defaultUserState = {
  accessToken: null,
  isAnonymous: true,
  featureFlagsWithDefaults: null,
  email: null,
  updateFlags: () => {
    throw new Error(
      'You are trying to use this context outside of a Provider container'
    )
  }
}

/** current user object context */
export const UserContext = React.createContext(defaultUserState)


/** Provider for the current user object.
  * this also exports plain JS methods for getting the token and flags,
  * since those may need to be accessible outside of React component rendering
  * e.g. in metrics-api
  */
export default function UserProvider({ user, children }) {
  const [userState, setUserState] = useState(user ? user : readUserInfoFromPage())

  userState.updateFeatureFlags = updateFeatureFlags
  userState.accessToken = getAccessToken()
  userState.isAnonymous = !userState.accessToken

  /** update the user's feature flags on the server */
  async function updateFeatureFlags(updatedFlags) {
    const mergedFlags = Object.assign({}, userState.featureFlagsWithDefaults, updatedFlags)
    const updatedUser = Object.assign({}, userState)
    updatedUser.featureFlagsWithDefaults = mergedFlags
    setUserState(updatedUser)
    // Note that we do NOT await the result of the server-side update
    // we want the UI to be able to change quickly in repsonse to a feature flag change, and
    // we assume changes will be successful (and it's not a big problem if they are not)
    updateCurrentUser({ feature_flags: updatedFlags })
  }
  return (
    <UserContext.Provider value={userState}>
      { children }
    </UserContext.Provider>
  )
}
