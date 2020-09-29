import React, { useState, useContext, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'

import { studyNameAsUrlParam, fetchAnnotationValues } from 'lib/scp-api'
import { UserContext } from 'providers/UserProvider'

/** This does NOT yet fully work!  It renders something dotplot like, but isn't handling annotations
  * properly yet */
export default function StudyGeneDotPlot({ study, genes }) {
  const userState = useContext(UserContext)
  const [isLoaded, setIsLoaded] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  /** fetch the expression data from the server */
  async function loadData() {
    setIsLoading(true)
    const annotations = await fetchAnnotationValues(study.accession)
    if (study.gene_matches.length > 1) {
      const geneParam = genes.join('+')
      window.renderMorpheusDotPlot(
        `/single_cell/study/${study.accession}/${studyNameAsUrlParam(study.name)}/expression_query?search[genes]=${geneParam}&row_centered=&row_centered=&cluster=&request_user_token=${userState.accessToken}`,
        `/single_cell/study/${study.accession}/${studyNameAsUrlParam(study.name)}/annotation_query?cluster=&annotation=&request_user_token=${userState.accessToken}`,
        'CLUSTER',
        'group',
        `#expGraph${study.accession}`,
        annotations,
        '',
        450,
        `#expGraph${study.accession}-legend`
      )
      setIsLoaded(true)
      setIsLoading(false)
    }
  }
  useEffect(() => {
    if (!isLoading && !isLoaded) {
      loadData()
    }
  })
  return (
    <div className="row">
      <div className="col-md-12">
        <div className="expression-graph" id={`expGraph${study.accession}`}></div>
        { isLoading && <FontAwesomeIcon icon={faDna} className="gene-load-spinner"/> }
      </div>
    </div>
  )
}
