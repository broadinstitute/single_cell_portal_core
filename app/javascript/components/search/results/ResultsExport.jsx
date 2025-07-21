import React, { useState } from 'react'
import Button from 'react-bootstrap/lib/Button'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faFileExport } from '@fortawesome/free-solid-svg-icons'
import { exportSearchResultsText } from '~/lib/scp-api'

export default function ResultsExport({ studySearchState }) {
  const hasResults = studySearchState?.results?.studies && studySearchState.results.studies.length > 0
  const [exporting, setExporting] = useState(false)

  /** export results to a file */
  async function exportResults() {
    setExporting(true)
    await exportSearchResultsText(studySearchState.params).then(() => {
      setExporting(false)
    })
  }

  return (
    <Button
      onClick={async () => {await exportResults()}}
      disabled={exporting || !hasResults}
      data-testid="export-search-results-tsv"
      data-analytics-name="export-search-results-tsv"
      data-original-title="Export search results to TSV file"
      data-toggle="tooltip"
    >
      <FontAwesomeIcon icon={faFileExport} /> {exporting ? 'Exporting...' : 'Export'}
    </Button>
  )
}
