import React, { useState, useEffect } from 'react'
import _clone from 'lodash/clone'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLink, faEye, faTimes, faUndo } from '@fortawesome/free-solid-svg-icons'

import ClusterSelector from '~/components/visualization/controls/ClusterSelector'
import AnnotationSelector from '~/components/visualization/controls/AnnotationSelector'
import SubsampleSelector from '~/components/visualization/controls/SubsampleSelector'
import { ExploreConsensusSelector } from '~/components/visualization/controls/ConsensusSelector'
import SpatialSelector from '~/components/visualization/controls/SpatialSelector'
import CreateAnnotation from '~/components/visualization/controls/CreateAnnotation'
import PlotDisplayControls from '~/components/visualization/PlotDisplayControls'
import GeneListSelector from '~/components/visualization/controls/GeneListSelector'
import InferCNVIdeogramSelector from '~/components/visualization/controls/InferCNVIdeogramSelector'
import { createCache } from './plot-data-cache'
import { getShownAnnotation, getDefaultSpatialGroupsForCluster } from '~/lib/cluster-utils'
import useResizeEffect from '~/hooks/useResizeEffect'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import DifferentialExpressionPanel, { DifferentialExpressionPanelHeader } from './DifferentialExpressionPanel'
import DifferentialExpressionModal from '~/components/explore/DifferentialExpressionModal'
import CellFilteringModal from '~/components/explore/CellFilteringModal'
import { CellFilteringPanel, CellFilteringPanelHeader } from './CellFilteringPanel'

/** Get the selected clustering and annotation, or their defaults */
function getSelectedClusterAndAnnot(exploreInfo, exploreParams) {
  const annotList = exploreInfo.annotationList
  let selectedCluster
  let selectedAnnot
  if (exploreParams?.cluster) {
    selectedCluster = exploreParams.cluster
    selectedAnnot = exploreParams.annotation
  } else {
    selectedCluster = annotList.default_cluster
    selectedAnnot = annotList.default_annotation
  }

  return [selectedCluster, selectedAnnot]
}

/** Determine if currently selected cluster has differential expression outputs available */
function getClusterHasDe(exploreInfo, exploreParams) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {return false}
  let clusterHasDe = false
  const selectedCluster = getSelectedClusterAndAnnot(exploreInfo, exploreParams)[0]

  clusterHasDe = exploreInfo.differentialExpression.some(deItem => {
    return (
      deItem.cluster_name === selectedCluster
    )
  })

  return clusterHasDe
}

/** Determine if current annotation has one-vs-rest or pairwise DE */
function getHasComparisonDe(exploreInfo, exploreParams, comparison) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {return false}

  const [selectedCluster, selectedAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)

  const hasComparisonDe = exploreInfo.differentialExpression.some(deItem => {
    return (
      deItem.cluster_name === selectedCluster &&
      deItem.annotation_name === selectedAnnot.name &&
      deItem.annotation_scope === selectedAnnot.scope &&
      deItem.select_options[comparison].length > 0
    )
  })

  return hasComparisonDe
}

/** Determine if current annotation has one-vs-rest or pairwise DE */
function getDeHeaders(exploreInfo, exploreParams) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {return false}

  const [selectedCluster, selectedAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)

  const deObject = exploreInfo.differentialExpression.find(deItem => {
    return (
      deItem.cluster_name === selectedCluster &&
      deItem.annotation_name === selectedAnnot.name &&
      deItem.annotation_scope === selectedAnnot.scope
    )
  })

  if (deObject) {
    const headers = deObject.select_options.headers
    if (headers.size === null) {
      headers.size = 'logfoldchanges'
      headers.significance = 'pvals_adj'
    }
    return headers
  } else {
    return null
  }
}

/** Return list of annotations that have differential expression enabled */
function getAnnotationsWithDE(exploreInfo) {
  if (!exploreInfo) {return false}

  let annotsWithDe = []

  annotsWithDe = exploreInfo.differentialExpression.filter(deItem => {
    return deItem
  }).map(annot => {
    return {
      cluster_name: annot.cluster_name,
      name: annot.annotation_name,
      scope: annot.annotation_scope,
      type: 'group'
    }
  })

  const clustersWithDe = Array.from(new Set(annotsWithDe.map(a => a.cluster_name)))

  return {
    clusters: clustersWithDe,
    annotations: annotsWithDe,
    subsample_thresholds: exploreInfo.annotationList.subsample_thresholds
  }
}


/** Determine if current annotation has differential expression results available */
function getAnnotHasDe(exploreInfo, exploreParams) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {
    // set isDifferentialExpressionEnabled to false as user cannot see DE results, even if present for annotation
    if (window.SCP) {
      window.SCP.isDifferentialExpressionEnabled = false
    }
    return false
  }

  let annotHasDe = false
  const [selectedCluster, selectedAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)

  annotHasDe = exploreInfo.differentialExpression.some(deItem => {
    return (
      deItem.cluster_name === selectedCluster &&
      deItem.annotation_name === selectedAnnot.name &&
      deItem.annotation_scope === selectedAnnot.scope
    )
  })

  return annotHasDe
}

/**
 * Determine if current annotation has differential expression results that are user-generated.
 *
 * DE results have two dimensions:
 * - Comparison type: either "one-vs-rest" or "pairwise"
 * - Source: "author-computed" "or SCP-computed"
 *
 * Author-computed DE is also often called "precomputed" or "user-uploaded" or "study-owner-generated"
 * or "custom".  Whereas SCP-generated DE is computed only for cell-type-like annotations and only as
 * one-vs-rest comparisons, user-generated DE can be more comprehensive -- it can be available for
 * any annotation, and as one-vs-rest and/or pairwise comparisons.
 */
function getIsAuthorDe(exploreInfo, exploreParams) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {
    return false
  }

  const [selectedCluster, selectedAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)

  const deItem = exploreInfo.differentialExpression.find(deItem => {
    return (
      deItem.cluster_name === selectedCluster &&
      deItem.annotation_name === selectedAnnot.name &&
      deItem.annotation_scope === selectedAnnot.scope
    )
  })

  const isAuthorDe = deItem?.select_options.is_author_de

  return isAuthorDe
}

/**
 * Manages the right panel section of the explore view of a study. We have three options for the right side
 * panel with different controls to adjust the plots: Options (or default), Differential Expression, and
 * Facet Filtering (currently in progress)
 *
 * This manager will return the correct content and header for the appropriate panel to display.
 *
 *  */
export default function ExploreDisplayPanelManager({
  studyAccession, exploreInfo, setExploreInfo, exploreParams, updateExploreParams, clearExploreParams,
  exploreParamsWithDefaults, routerLocation, searchGenes, countsByLabel, setShowUpstreamDifferentialExpressionPanel,
  setShowDifferentialExpressionPanel, showUpstreamDifferentialExpressionPanel, togglePanel, shownTab,
  showDifferentialExpressionPanel, setIsCellSelecting, currentPointsSelected, isCellSelecting, deGenes,
  setDeGenes, setShowDeGroupPicker, cellFaceting, cellFilteringSelection, clusterCanFilter, filterErrorText,
  updateFilteredCells, panelToShow, toggleViewOptions
}) {
  const [, setRenderForcer] = useState({})
  const [dataCache] = useState(createCache())

  const [deGroupB, setDeGroupB] = useState(null)
  const [deGroup, setDeGroup] = useState(null)

  const showCellFiltering = getFeatureFlagsWithDefaults()?.show_cell_facet_filtering


  // Differential expression settings
  const flags = getFeatureFlagsWithDefaults()
  // `differential_expression_frontend` enables exemptions if study owners don't want DE
  const studyHasDe = flags?.differential_expression_frontend && exploreInfo?.differentialExpression.length > 0
  const annotHasDe = getAnnotHasDe(exploreInfo, exploreParams)
  const clusterHasDe = getClusterHasDe(exploreInfo, exploreParams)
  const hasOneVsRestDe = getHasComparisonDe(exploreInfo, exploreParams, 'one_vs_rest')
  const hasPairwiseDe = getHasComparisonDe(exploreInfo, exploreParams, 'pairwise')
  const deHeaders = getDeHeaders(exploreInfo, exploreParams)
  const isAuthorDe = getIsAuthorDe(exploreInfo, exploreParams)

  // exploreParams object without genes specified, to pass to cluster comparison plots
  const referencePlotDataParams = _clone(exploreParams)

  referencePlotDataParams.genes = []

  const annotationList = exploreInfo ? exploreInfo.annotationList : null
  // hide the cluster controls if we're on a genome tab, or if there aren't clusters to choose
  const showClusterControls = !['genome', 'infercnv-genome', 'geneListHeatmap'].includes(shownTab) &&
                                annotationList?.clusters?.length

  let hasSpatialGroups = false
  if (exploreInfo) {
    hasSpatialGroups = exploreInfo.spatialGroups.length > 0
  }

  const shownAnnotation = getShownAnnotation(exploreParamsWithDefaults.annotation, annotationList)

  const isSubsampled = exploreParamsWithDefaults.subsample !== 'all'
  let cellFilteringTooltipAttrs = {}
  if (isSubsampled) {
    cellFilteringTooltipAttrs = {
      'data-toggle': 'tooltip',
      'data-original-title': 'Clicking will remove subsampling; plots might be noticeably slower.'
    }
  }

  /** Toggle cell filtering panel, and remove subsampling if needed */
  function toggleCellFilterPanel() {
    if (isSubsampled) {
      updateClusterParams({ subsample: 'All Cells' })
      document.querySelector('.tooltip.fade.top.in').remove()
    }
    togglePanel('cell-filtering')
  }

  /** in the event a component takes an action which updates the list of annotations available
    * e.g. by creating a user annotation, this updates the list */
  function setAnnotationList(newAnnotationList) {
    const newExploreInfo = Object.assign({}, exploreInfo, { annotationList: newAnnotationList })
    setExploreInfo(newExploreInfo)
  }

  /** copies the url to the clipboard */
  function copyLink(routerLocation) {
    navigator.clipboard.writeText(routerLocation.href)
  }

  /** handles cluster selection to also populate the default spatial groups */
  function updateClusterParams(newParams) {
    if (newParams.cluster && !newParams.spatialGroups) {
      newParams.spatialGroups = getDefaultSpatialGroupsForCluster(newParams.cluster, exploreInfo.spatialGroups)
      dataCache.clear()
    }

    // if the user updates any cluster params, store all of them in the URL so we don't end up with
    // broken urls in the event of a default cluster/annotation changes
    // also, unset any gene lists as we're about to re-render the explore tab and having gene list selected will show
    // the wrong tabs
    const updateParams = { geneList: '', ideogramFileId: '' }

    const clusterParamNames = ['cluster', 'annotation', 'subsample', 'spatialGroups']
    clusterParamNames.forEach(param => {
      updateParams[param] = param in newParams ? newParams[param] : exploreParamsWithDefaults[param]
    })
    // if a user switches to a numeric annotation, change the tab to annotated scatter (SCP-3833)
    if (newParams.annotation?.type === 'numeric' &&
      exploreParamsWithDefaults.genes?.length &&
      exploreParamsWithDefaults.annotation?.type !== 'numeric'
    ) {
      updateParams.tab = 'annotatedScatter'
    }
    // if the user changes annotation, unset hiddenTraces
    if (newParams.annotation && newParams.annotation.name !== exploreParams.annotation.name) {
      updateParams.hiddenTraces = []
    }

    updateExploreParams(updateParams)
  }

  /** handles gene list selection */
  function updateGeneList(geneListName) {
    const geneListInfo = exploreInfo.geneLists.find(gl => gl.name === geneListName)
    if (!geneListInfo) {
      updateExploreParams({ geneList: '', heatmapRowCentering: '', heatmapFit: '' })
    } else {
      updateExploreParams({
        geneList: geneListName,
        heatmapRowCentering: '',
        heatmapFit: 'both',
        genes: []
      })
    }
  }

  /** handles updating inferCNV/ideogram selection */
  function updateInferCNVIdeogramFile(annotationFile) {
    updateExploreParams({ ideogramFileId: annotationFile, tab: 'infercnv-genome' })
  }

  /** if the user hasn't selected anything, and there are genelists to view, but no clusters
    * default to the first gene list */
  useEffect(() => {
    if ((exploreInfo && exploreInfo.annotationList.clusters.length === 0 &&
      exploreInfo.geneLists.length && !exploreParams.tab && !exploreParams.geneList)) {
      updateGeneList(exploreInfo.geneLists[0].name)
    }
  }, [exploreInfo?.geneLists])

  /** on window resize call setRenderForcer, which is just trivial state to ensure a re-render
   * ensuring that the plots get passed fresh dimensions */
  useResizeEffect(() => {
    setRenderForcer({})
  }, 300)

  return (
    <>
      <div>
        {/* Render "Options" panel at right of page */}
        <div className="view-options-toggle">
          {panelToShow === 'options' &&
              <>
                <FontAwesomeIcon className="fa-lg" icon={faEye}/> <span className="options-label">OPTIONS</span>
                <button className={`action ${showDifferentialExpressionPanel ? '' : 'action-with-bg'}`}
                  onClick={toggleViewOptions}
                  title="Hide options"
                  data-analytics-name="view-options-hide">
                  <FontAwesomeIcon className="fa-lg" icon={faTimes}/>
                </button>
              </>
          }
          {showCellFiltering && panelToShow === 'cell-filtering' &&
            <CellFilteringPanelHeader
              togglePanel={togglePanel}
              setShowDifferentialExpressionPanel={setShowDifferentialExpressionPanel}
              setShowUpstreamDifferentialExpressionPanel={setShowUpstreamDifferentialExpressionPanel}
              isUpstream={showUpstreamDifferentialExpressionPanel}
              cluster={exploreParamsWithDefaults.cluster}
              annotation={shownAnnotation}
              setDeGroupB={setDeGroupB}
              isAuthorDe={isAuthorDe}
              updateFilteredCells={updateFilteredCells}
              deGenes={deGenes}
            />
          }
          {panelToShow === 'differential-expression' &&
              <DifferentialExpressionPanelHeader
                setDeGenes={setDeGenes}
                setDeGroup={setDeGroup}
                setShowDifferentialExpressionPanel={setShowDifferentialExpressionPanel}
                setShowUpstreamDifferentialExpressionPanel={setShowUpstreamDifferentialExpressionPanel}
                isUpstream={showUpstreamDifferentialExpressionPanel}
                cluster={exploreParamsWithDefaults.cluster}
                annotation={shownAnnotation}
                setDeGroupB={setDeGroupB}
                isAuthorDe={isAuthorDe}
                deGenes={deGenes}
                togglePanel={togglePanel}
              />
          }
        </div>
        {panelToShow === 'options' &&
          <>
            <div>
              <div className={showClusterControls ? '' : 'hidden'}>
                <ClusterSelector
                  annotationList={annotationList}
                  cluster={exploreParamsWithDefaults.cluster}
                  annotation={exploreParamsWithDefaults.annotation}
                  updateClusterParams={updateClusterParams}
                  spatialGroups={exploreInfo ? exploreInfo.spatialGroups : []}/>
                {hasSpatialGroups &&
                <SpatialSelector allSpatialGroups={exploreInfo.spatialGroups}
                  spatialGroups={exploreParamsWithDefaults.spatialGroups}
                  updateSpatialGroups={spatialGroups => updateClusterParams({ spatialGroups })}/>
                }
                <AnnotationSelector
                  annotationList={annotationList}
                  cluster={exploreParamsWithDefaults.cluster}
                  shownAnnotation={shownAnnotation}
                  updateClusterParams={updateClusterParams}/>
                { shownTab === 'scatter' && <CreateAnnotation
                  isSelecting={isCellSelecting}
                  setIsSelecting={setIsCellSelecting}
                  annotationList={exploreInfo ? exploreInfo.annotationList : null}
                  currentPointsSelected={currentPointsSelected}
                  cluster={exploreParamsWithDefaults.cluster}
                  annotation={exploreParamsWithDefaults.annotation}
                  subsample={exploreParamsWithDefaults.subsample}
                  updateClusterParams={updateClusterParams}
                  setAnnotationList={setAnnotationList}
                  studyAccession={studyAccession}/>
                }
                {studyHasDe &&
                <>
                  <div className="row de-modal-row-wrapper">
                    <div className="col-xs-12 de-modal-row">
                      <button
                        className=
                          {`btn btn-primary differential-expression${annotHasDe ? '' : '-nondefault'}`}
                        onClick={() => {
                          if (annotHasDe) {
                            setShowDifferentialExpressionPanel(true)
                            setShowDeGroupPicker(true)
                            togglePanel('differential-expression')
                          } else if (studyHasDe) {
                            setShowUpstreamDifferentialExpressionPanel(true)
                            togglePanel('differential-expression')
                          }
                        }}
                      >Differential expression</button>
                      <DifferentialExpressionModal />
                    </div>
                  </div>
                </>
                }
                { showCellFiltering && clusterCanFilter &&
                  <>
                    <div className="row">
                      <div className="col-xs-12 cell-filtering-button">
                        <button
                          className={`btn btn-primary`}
                          data-testid="cell-filtering-button"
                          {...cellFilteringTooltipAttrs}
                          onClick={() => toggleCellFilterPanel()}
                        >Cell filtering</button>
                        <CellFilteringModal />
                      </div>
                    </div>
                  </>
                }
                { showCellFiltering && !clusterCanFilter &&
                  <>
                    <div className="row">
                      <div className="col-xs-12 cell-filtering-button">
                        <button
                          disabled="disabled"
                          className={`btn btn-primary`}
                          data-testid="cell-filtering-button"
                          data-toggle="tooltip"
                          data-original-title={`Cell filtering cannot be displayed for this selection: ${filterErrorText}.`}
                        >Filtering unavailable</button>
                      </div>
                    </div>
                  </>
                }
                <SubsampleSelector
                  annotationList={annotationList}
                  cluster={exploreParamsWithDefaults.cluster}
                  subsample={exploreParamsWithDefaults.subsample}
                  updateClusterParams={updateClusterParams}/>
              </div>
              { exploreInfo?.geneLists?.length > 0 &&
              <GeneListSelector
                geneList={exploreParamsWithDefaults.geneList}
                studyGeneLists={exploreInfo.geneLists}
                selectLabel={exploreInfo.precomputedHeatmapLabel ?? undefined}
                updateGeneList={updateGeneList}/>
              }
              { exploreParams.genes?.length > 1 && !['genome', 'infercnv-genome'].includes(shownTab) &&
              <ExploreConsensusSelector
                consensus={exploreParamsWithDefaults.consensus}
                updateConsensus={consensus => updateExploreParams({ consensus })}/>
              }
              { !!exploreInfo?.inferCNVIdeogramFiles &&
                <InferCNVIdeogramSelector
                  inferCNVIdeogramFile={exploreParamsWithDefaults.ideogramFileId}
                  studyInferCNVIdeogramFiles={exploreInfo.inferCNVIdeogramFiles}
                  updateInferCNVIdeogramFile={updateInferCNVIdeogramFile}
                />
              }
            </div>
            <PlotDisplayControls
              shownTab={shownTab}
              exploreParams={exploreParamsWithDefaults}
              updateExploreParams={updateExploreParams}
              allGenes={exploreInfo ? exploreInfo.uniqueGenes : []}/>
            <button className="action action-with-bg margin-extra-right"
              onClick={clearExploreParams}
              title="Reset all view options"
              data-analytics-name="explore-view-options-reset">
              <FontAwesomeIcon icon={faUndo}/> Reset view
            </button>
            <button onClick={() => copyLink(routerLocation)}
              className="action action-with-bg"
              data-toggle="tooltip"
              title="Copy a link to this visualization to the clipboard">
              <FontAwesomeIcon icon={faLink}/> Get link
            </button>
          </>
        }
        {showCellFiltering && panelToShow === 'cell-filtering' && clusterCanFilter &&
        <CellFilteringPanel
          annotationList={annotationList}
          cluster={exploreParamsWithDefaults.cluster}
          shownAnnotation={shownAnnotation}
          updateClusterParams={updateClusterParams}
          cellFaceting={cellFaceting}
          cellFilteringSelection={cellFilteringSelection}
          updateFilteredCells={updateFilteredCells}
          exploreParams={exploreParams}
          exploreInfo={exploreInfo}
          studyAccession={studyAccession}
        />}
        {panelToShow === 'differential-expression' && countsByLabel && annotHasDe &&
          <>
            <DifferentialExpressionPanel
              deGroup={deGroup}
              deGenes={deGenes}
              searchGenes={searchGenes}
              exploreParamsWithDefaults={exploreParamsWithDefaults}
              exploreInfo={exploreInfo}
              clusterName={exploreParamsWithDefaults.cluster}
              annotation={shownAnnotation}
              setShowDeGroupPicker={setShowDeGroupPicker}
              setDeGenes={setDeGenes}
              setDeGroup={setDeGroup}
              hasOneVsRestDe={hasOneVsRestDe}
              hasPairwiseDe={hasPairwiseDe}
              isAuthorDe={isAuthorDe}
              deHeaders={deHeaders}
              deGroupB={deGroupB}
              setDeGroupB={setDeGroupB}
              countsByLabel={countsByLabel}
              togglePanel={togglePanel}
            />
          </>
        }
        {showUpstreamDifferentialExpressionPanel &&
          <>
            {!clusterHasDe &&
            <>
              <ClusterSelector
                annotationList={getAnnotationsWithDE(exploreInfo)}
                cluster={''}
                annotation={''}
                updateClusterParams={updateClusterParams}
                hasSelection={false}
                spatialGroups={exploreInfo ? exploreInfo.spatialGroups : []}/>
            </>
            }
            {clusterHasDe &&
              <AnnotationSelector
                annotationList={getAnnotationsWithDE(exploreInfo)}
                cluster={exploreParamsWithDefaults.cluster}
                shownAnnotation={shownAnnotation}
                updateClusterParams={updateClusterParams}
                hasSelection={false}
                setShowDifferentialExpressionPanel={setShowDifferentialExpressionPanel}
                setShowUpstreamDifferentialExpressionPanel={setShowUpstreamDifferentialExpressionPanel}
              />
            }
          </>
        }
      </div>
    </>
  )
}
