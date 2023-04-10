// JS variables wrapped in double underscores are defined in version.txt
const version = (typeof __SCP_VERSION__ !== 'undefined') ? __SCP_VERSION__ : null
const devMode = (typeof __DEV_MODE__ !== 'undefined') ? __DEV_MODE__ : null

// Set by running the following in terminal in local SCP instance:
// VITE_FRONTEND_SERVICE_WORKER_CACHE="true" bin/vite dev
export const isServiceWorkerCacheEnabled = (typeof __FRONTEND_SERVICE_WORKER_CACHE__ !== 'undefined') ? __FRONTEND_SERVICE_WORKER_CACHE__ : false

/**  wrapper around window.SCP to enumerate properties the React frontend expects from the server */
export function getSCPContext() {
  if (window.SCP) {
    window.SCP.version = version
    window.SCP.isServiceWorkerCacheEnabled = isServiceWorkerCacheEnabled
    window.SCP.devMode = devMode
    return window.SCP
  }
  return {
    userAccessToken: 'test',
    environment: 'test',
    analyticsPageName: 'test-noname',
    version,
    isServiceWorkerCacheEnabled,
    devMode
  }
}
