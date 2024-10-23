import React from 'react'
import { parseAnnotationName } from '~/components/explore/FacetComponents'

const maxMetadataEntities = 2

// strip off redundant information like '(disease)' from the end of labels
// also accounts for array-based labels with pipes |
function sanitizeMetadataLabel(label) {
  const allLabels = label.match('|') ? label.split('|') : [label]
  const returnLabels = []
  allLabels.map(subLabel => {
    if (subLabel.endsWith('(disease)')) {
      returnLabels.push(subLabel.split(' (disease)')[0])
    } else {
      returnLabels.push(subLabel)
    }
  })
  return returnLabels.join('|')
}

// show list of metadata values as badges, truncating as needed
function metadataList(values, accession, header) {
  const moreValues = values.splice(maxMetadataEntities)
  const list = values.map((val, i) => {
    return <span key={`${accession}-${header}-entry-${i}-val`}
                 className="badge badge-secondary facet-match study-metadata-entry">{sanitizeMetadataLabel(val)}</span>
  })
  if (moreValues.length > 0) {
    list.push(<span key={`${accession}-${header}-entry-extra`}
                    className="badge badge-secondary facet-match study-metadata-entry more-metadata-entries"
                    data-toggle="tooltip"
                    data-original-title={`${moreValues.map(v => {return sanitizeMetadataLabel(v)}).join(', ')}`}
    >{moreValues.length} more...</span>)
  }
  if (list.length === 0) {
    list.push(<span key={`${accession}-${header}-entry-unspecified-val`}
                    className="badge study-metadata-entry unspecified-entry">unspecified</span>)
  }
  return list
}

// return a table with the 5 top-level metadata entries and their values for a SCP study
export default function ResultMetadataTable({study}) {
  const headers = []
  const studyValues = []
  const tableId = `${study.accession}-cohort-metadata`

  Object.entries(study.metadata).map((entry, index) => {
    const header = parseAnnotationName(entry[0])[0]
    const data = entry[1]
    const values = metadataList(data, study.accession, header)
    headers.push(<th className="cohort-th" key={`${study.accession}-${header}-th`}>{header}</th>)
    studyValues.push(<td className="cohort-td" key={`${study.accession}-${header}-metadata-${index}-td`}>{values}</td>)
  })

  return <div className="table-responsive">
    <table className="table table-condensed cohort-metadata-table" id={tableId} data-testid={tableId}>
      <thead>
      <tr>
        {headers}
      </tr>
      </thead>
      <tbody>
      <tr>
        {studyValues}
      </tr>
      </tbody>
    </table>
  </div>
}
