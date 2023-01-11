import React, { Component } from 'react'
import { logError } from '~/lib/metrics-api'
import { supportEmailLink } from '~/lib/error-utils'
import { logJSFetchErrorToSentry } from '~/lib/sentry-logging'

/** convert to readable message  e.g.
 * "foobar is not defined    in ResultsPanel (at HomePageContent.js:22)"
 */
function readableErrorMessage(error, info) {
  // the first line of info stack seems to always be blank,
  // so add the second one to the message

  // the error.stack is typically useless because EventBoundaries do NOT catch
  // errors in event handlers, so the error.stack is just full of react internals
  return error.message + info.componentStack.split('\n')[1]
}

/**
 * See https://reactjs.org/docs/error-boundaries.html
 * note that this must be a class component
 * as hooks do not support componentDidCatch yet
 */
export default class ErrorBoundary extends Component {
  /** initialize to a non-error state */
  constructor(props) {
    super(props)
    this.state = { error: null }
  }

  /** log an error, and then update the display to show the error */
  componentDidCatch(error, info) {
    console.error(error)
    // log error to Mixpanel
    logError(readableErrorMessage(error, info))
    // log error to Sentry
    logJSFetchErrorToSentry(error, readableErrorMessage(error, info))
    this.setState({ error, info })
  }

  /** show an error if one exists, otherwise show the component */
  render() {
    if (this.state.error) {
      return (
        <div className="alert-danger text-center error-boundary">
          <span className="font-italic ">Something went wrong.</span><br/>
          <span>
            Please try reloading the page. If this error persists, or you require assistance, please
            contact support at
            <br/>
            {supportEmailLink} and include the error text below.
          </span>
          <pre>
          </pre>
        </div>
      )
    }

    return this.props.children
  }
}
/** HOC for wrapping arbitrary components in error boundaries */
export function withErrorBoundary(Component) {
  return function SafeWrappedComponent(props) {
    return (
      <ErrorBoundary>
        <Component {...props} />
      </ErrorBoundary>
    )
  }
}
