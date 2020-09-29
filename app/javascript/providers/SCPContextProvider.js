//  wrapper around window.SCP to enumerate properties the React frontend expects from the server
export default function getSCPContext() {
  if (window.SCP) {
    return window.SCP
  }
  return {
    userAccessToken: 'test',
    environment: 'test',
    analyticsPageName: 'test-noname'
  }
}
