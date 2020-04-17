import React, { Component } from 'react'
import { logError } from 'lib/metrics-api'
/* convert to readable message  e.g.
 * "foobar is not defined    in ResultsPanel (at HomePageContent.js:22)"
 */
function readableErrorMessage(error, info) {
  // the first line of info stack seems to always be blank,
  // so add the second one to the message

  // the error.stack is typically useless because EventBoundaries do NOT catch
  // errors in event handlers, so the error.stack is just full of react internals
  return error.message + info.componentStack.split('\n')[1]
}

/*
 * See https://reactjs.org/docs/error-boundaries.html
 * note that this must be a class component
 * as hooks do not support componentDidCatch yet
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { error: null }
  }

  componentDidCatch(error, info) {
    logError(readableErrorMessage(error, info))
    this.setState({ error, info })
  }

  render() {
    if (this.state.error) {
      // consider using node_env to decide whether or not to render the full trace
      // See related ticket SCP-2237
      return (
        <div className="alert-danger text-center error-boundary">
          <span className="font-italic ">Something went wrong.</span><br/>
          {readableErrorMessage(this.state.error, this.state.info)}
        </div>
      )
    }

    return this.props.children
  }
}
// HOC for wrapping arbitrary components in error boundaries
export function withErrorBoundary(Component) {
  return function SafeWrappedComponent(props) {
    return (
      <ErrorBoundary>
        <Component {...props} />
      </ErrorBoundary>
    )
  }
}
