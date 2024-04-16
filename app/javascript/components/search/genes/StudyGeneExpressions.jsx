import React, { useState, useEffect } from 'react'
import _clone from 'lodash/clone'

import StudySearchResult, { getByline } from '~/components/search/results/StudySearchResult'
import DotPlot from '~/components/visualization/DotPlot'
import StudyViolinPlot from '~/components/visualization/StudyViolinPlot'
import ScatterPlot from '~/components/visualization/ScatterPlot'
import ClusterSelector from '~/components/visualization/controls/ClusterSelector'
import AnnotationSelector from '~/components/visualization/controls/AnnotationSelector'
import SubsampleSelector from '~/components/visualization/controls/SubsampleSelector'
import ConsensusSelector from '~/components/visualization/controls/ConsensusSelector'
import { fetchClusterOptions } from '~/lib/scp-api'
import {
  getDefaultClusterParams, getAnnotationValues, emptyDataParams
} from '~/lib/cluster-utils'


/** Renders expression data for a study.  This assumes that the study has a 'gene_matches' property
    to inform which genes to show data for
  */
export default function StudyGeneExpressions({ study }) {
  const [clusterParams, setClusterParams] = useState(_clone(emptyDataParams))
  const [annotationList, setAnnotationList] = useState(getNonUserAnnotations(study))
  let controlClusterParams = _clone(clusterParams)
  if (annotationList && !clusterParams.cluster) {
    // if the user hasn't specified anything yet, but we have the study defaults, use those
    controlClusterParams = Object.assign(controlClusterParams, getDefaultClusterParams(annotationList))
  }

  let studyRenderComponent
  if (!study.gene_matches) {
    return <StudySearchResult study={study}/>
  }
  const isMultiGene = study.gene_matches.length > 1
  const showDotPlot = isMultiGene && !clusterParams.consensus
  const isNumericAnnotation = controlClusterParams.annotation.type === 'numeric'

  if (!study.can_visualize_clusters) {
    studyRenderComponent = (
      <div className="text-center">
        This study contains {study.gene_matches.join(', ')} in expression data.<br/>
          This study does not have cluster data to support visualization in the portal
      </div>
    )
  } else if (showDotPlot) {
    // render dotPlot for multigene searches that are not collapsed
    const annotationValues = getAnnotationValues(controlClusterParams.annotation, annotationList)
    const [morpheusData, setMorpheusData] = useState(null)
    studyRenderComponent = <DotPlot studyAccession={study.accession}
      genes={study.gene_matches}
      setMorpheusData={setMorpheusData}
      {...controlClusterParams}
      annotationValues={annotationValues}/>
  } else if (isNumericAnnotation) {
    // render annotated scatter plot if the viewed annotation is of type "numeric"
    studyRenderComponent = <ScatterPlot
      studyAccession={study.accession}
      genes={study.gene_matches}
      {...controlClusterParams}
      isAnnotatedScatter={true}
      dimensionProps={{ verticalPad: 400 }}
    />
  } else {
    // render violin for single genes or collapsed
    studyRenderComponent = <StudyViolinPlot
      studyAccession={study.accession}
      genes={study.gene_matches}
      {...controlClusterParams}
      setAnnotationList={setAnnotationList}/>
  }

  /** handles cluster selection to also populate the default spatial groups */
  function updateClusterParams(newParams) {
    // if the user updates any cluster params, store all of them in the URL so we don't end up with
    // broken urls in the event of a default cluster/annotation changes
    setClusterParams(Object.assign({}, controlClusterParams, newParams))
  }

  useEffect(() => {
    // if showing a dotplot, we need to fetch the annotation values to feed into morpheus
    if (study.can_visualize_clusters && showDotPlot) {
      fetchClusterOptions(study.accession).then(newAnnotationList => setAnnotationList(newAnnotationList))
    }
  }, [study.accession])

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
      <div className="row graph-container">
        <div className={study.can_visualize_clusters ? 'col-md-10' : 'col-md-12'}>
          { studyRenderComponent }
        </div>
        { study.can_visualize_clusters &&
          <div className="col-md-2 graph-controls">
            <div className="cluster-controls">
              <ClusterSelector
                annotationList={annotationList}
                {...controlClusterParams}
                updateClusterParams={updateClusterParams}/>
              <AnnotationSelector
                annotationList={annotationList}
                shownAnnotation={controlClusterParams.annotation}
                {...controlClusterParams}
                updateClusterParams={updateClusterParams}/>
              <SubsampleSelector
                annotationList={annotationList}
                {...controlClusterParams}
                updateClusterParams={updateClusterParams}/>
              { isMultiGene &&
                <ConsensusSelector
                  {...controlClusterParams}
                  updateConsensus={consensus => updateClusterParams({ consensus })}/>
              }
            </div>
          </div>
        }
      </div>

    </div>
  )
}

/**
 * Get annotations that aren't custom
 *
 * TODO (SCP-4242): Handle custom annotations in global gene search,
 * then remove this function.
 */
function getNonUserAnnotations(study) {
  let basicAnnotationList = null
  if (study.can_visualize_clusters) {
    basicAnnotationList = study.annotation_list
    basicAnnotationList.annotations = basicAnnotationList.annotations.filter(a => a.scope !== 'user')
  }
  return basicAnnotationList
}
