import React from 'react'

import Study, { getByline } from 'components/search/results/Study'
// import StudyGeneDotPlot from './StudyGeneDotPlot'
import StudyViolinPlot from './StudyViolinPlot'


/** Renders expression data for a study.  This assumes that the study has a 'gene_matches' property
    to inform which genes to show data for
  */
export default function StudyGeneExpressions({ study }) {
  let studyRenderComponent
  if (!study.gene_matches) {
    return <Study study={study}/>
  }
  if (!study.can_visualize_clusters) {
    studyRenderComponent = (
      <div className="text-center">
        This study contains {study.gene_matches.join(', ')} in expression data.<br/>
          This study does not have cluster data to support visualization in the portal
      </div>
    )
  } else if (study.gene_matches.length > 1) {
    // for now, this renders a bunch of violins, we should soon ugrade to dot plots
    // <StudyGeneDotPlot study={study} genes={study.gene_matches}/>
    studyRenderComponent = study.gene_matches.map(gene => {
      return <StudyViolinPlot key={gene} study={study} gene={gene}/>
    })
  } else {
    studyRenderComponent = <StudyViolinPlot study={study} gene={study.gene_matches[0]}/>
  }
  return (
    <div className="study-gene-result">
      <label htmlFor={study.name} id= 'result-title'>
        <a href={study.study_url} >{ study.name }</a>
      </label>
      <div ><em>{ getByline(study.description) }</em></div>
      <div>
        <span className='badge badge-secondary cell-count'>
          {study.cell_count} Cells
        </span>
        {
          study.gene_matches.map(geneName => {
            return (<span key={geneName} className='badge gene-match'>
              { geneName }
            </span>)
          })
        }
      </div>
      { studyRenderComponent }
    </div>
  )
}
