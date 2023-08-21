import React from 'react'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna, faSpinner } from '@fortawesome/free-solid-svg-icons'

/** show dna spinning indicator.
 * If no arguments or children are passed in, the spinner is rendered
 * Alternatively, children can be passed in, in which case either the spinner or the children
 * are rendered, contingent on the isLoading property
 */
export default function LoadingSpinner({ children, testId, isLoading, className='gene-load-spinner' }) {
  // allow additional custom css for the spinner
  const fullClassName = className === 'gene-load-spinner' ? className : `gene-load-spinner ${className}`

  const spinner = <FontAwesomeIcon icon={faDna} className={fullClassName} data-testid={testId}/>
  if (!children && typeof(isLoading) === 'undefined') {
    return spinner
  }
  return <>
    {isLoading && spinner}
    {!isLoading &&
      children
    }
  </>
}

/**
 * loading spinner specific to Morpheus - needed for JSON dataset
 * includes outer wrapper to align to viewport properly
 */
export function morpheusLoadingSpinner() {
  return `
    <div style="overflow:hidden;text-align:center;">
      <i class="fas fa-spinner fa-spin fa-3x"></i>
      <span style="padding-left:4px;vertical-align:middle;font-weight:bold;">Loading...</span>
    </div>
  `
}
