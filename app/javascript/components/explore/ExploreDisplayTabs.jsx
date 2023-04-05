import React, { useState, useEffect } from 'react'
import _clone from 'lodash/clone'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLink, faArrowLeft, faCog, faTimes, faUndo } from '@fortawesome/free-solid-svg-icons'

import StudyGeneField from './StudyGeneField'
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
import ScatterTab from './ScatterTab'
import PlotUtils from '~/lib/plot'
const getPlotDimensions = PlotUtils.getPlotDimensions
import ScatterPlot from '~/components/visualization/ScatterPlot'
import StudyViolinPlot from '~/components/visualization/StudyViolinPlot'
import DotPlot from '~/components/visualization/DotPlot'
import Heatmap from '~/components/visualization/Heatmap'
import GeneListHeatmap from '~/components/visualization/GeneListHeatmap'
import GenomeView from './GenomeView'
import ImageTab from './ImageTab'
import { getAnnotationValues, getShownAnnotation, getDefaultSpatialGroupsForCluster } from '~/lib/cluster-utils'
import RelatedGenesIdeogram from '~/components/visualization/RelatedGenesIdeogram'
import InferCNVIdeogram from '~/components/visualization/InferCNVIdeogram'
import useResizeEffect from '~/hooks/useResizeEffect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { log } from '~/lib/metrics-api'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import DifferentialExpressionPanel, { DifferentialExpressionPanelHeader } from './DifferentialExpressionPanel'
import OverlayTrigger from 'react-bootstrap/lib/OverlayTrigger'
import Tooltip from 'react-bootstrap/lib/Tooltip'
import DifferentialExpressionModal from '~/components/explore/DifferentialExpressionModal'

const tabList = [
  { key: 'loading', label: 'loading...' },
  { key: 'scatter', label: 'Scatter' },
  { key: 'annotatedScatter', label: 'Annotated scatter' },
  { key: 'correlatedScatter', label: 'Correlation' },
  { key: 'distribution', label: 'Distribution' },
  { key: 'dotplot', label: 'Dot plot' },
  { key: 'heatmap', label: 'Heatmap' },
  { key: 'geneListHeatmap', label: 'Precomputed heatmap' },
  { key: 'spatial', label: 'Spatial' },
  { key: 'genome', label: 'Genome' },
  { key: 'infercnv-genome', label: 'Genome (inferCNV)' },
  { key: 'images', label: 'Images' }
]

/** Determine if currently selected cluster has differential expression outputs available */
function getClusterHasDe(exploreInfo, exploreParams) {
  const flags = getFeatureFlagsWithDefaults()
  if (!flags?.differential_expression_frontend || !exploreInfo) {return false}
  let clusterHasDe = false
  const annotList = exploreInfo.annotationList
  let selectedCluster
  if (exploreParams?.cluster) {
    selectedCluster = exploreParams.cluster
  } else {
    selectedCluster = annotList.default_cluster
  }

  clusterHasDe = exploreInfo.differentialExpression.some(deItem => {
    return (
      deItem.cluster_name === selectedCluster
    )
  })

  return clusterHasDe
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

/** Determine if currently selected annotation has differential expression outputs available */
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
 * Renders the gene search box and the tab selection
 * Responsible for determining which tabs are available for a given view of the study
 *
 * We want to mount all components that are enabled, so they can fetch their data and persist
 * even when they are not currently in view. We don't want to mount non-enabled components
 * as their display doesn't make sense with the current dataParams, and so they will
 * need to re-render on dataParams change anyway
 *
 * @param {String} studyAccession  the study accession to visualize
 * @param {Object} exploreInfo  the object returned from a call to api/v1/studies/{study}/visualization/explore
 * @param {Object} dataParams  object with cluster, annotation, and other viewing properties specified.
 * @param { Function } updateDataParams function for passing updates to the dataParams object
 */
export default function ExploreDisplayTabs({
  studyAccession, exploreInfo, setExploreInfo, exploreParams, updateExploreParams,
  clearExploreParams, exploreParamsWithDefaults, routerLocation
}) {
  const [, setRenderForcer] = useState({})
  const [dataCache] = useState(createCache())
  // tracks whether the view options controls are open or closed
  const [showViewOptionsControls, setShowViewOptionsControls] = useState(true)
  // whether the user is in lasso-select mode for selecting points for an annotation
  const [isCellSelecting, setIsCellSelecting] = useState(false)
  // a plotly points_selected event
  const [currentPointsSelected, setCurrentPointsSelected] = useState(null)

  // Differential expression settings
  const flags = getFeatureFlagsWithDefaults()
  const studyHasDe = flags?.differential_expression_frontend && exploreInfo?.differentialExpression.length > 0
  const annotHasDe = getAnnotHasDe(exploreInfo, exploreParams)
  const clusterHasDe = getClusterHasDe(exploreInfo, exploreParams)

  const [, setShowDeGroupPicker] = useState(false)
  const [deGenes, setDeGenes] = useState(null)
  const [deGroup, setDeGroup] = useState(null)
  const [showDifferentialExpressionPanel, setShowDifferentialExpressionPanel] = useState(deGenes !== null)
  const [showUpstreamDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel] = useState(deGenes !== null)

  // Hash of trace label names to the number of points in that trace
  const [countsByLabel, setCountsByLabel] = useState(null)

  const plotContainerClass = 'explore-plot-tab-content'

  const {
    enabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs
  } = getEnabledTabs(exploreInfo, exploreParamsWithDefaults)

  // exploreParams object without genes specified, to pass to cluster comparison plots
  const referencePlotDataParams = _clone(exploreParams)
  referencePlotDataParams.genes = []

  /** helper function so that StudyGeneField doesn't have to see the full exploreParams object */
  function searchGenes(genes) {
    // also unset any selected gene lists or ideogram files
    const newParams = { genes, geneList: '', ideogramFileId: '' }
    if (genes.length < 2) {
      // and unset the consensus if there are no longer 2+ genes
      newParams.consensus = ''
    }
    updateExploreParams(newParams)
  }

  let shownTab = exploreParams.tab
  if (!enabledTabs.includes(shownTab)) {
    shownTab = enabledTabs[0]
  }
  let showRelatedGenesIdeogram = false
  let currentTaxon = null
  let searchedGene = null
  if (
    exploreInfo &&
    exploreInfo.taxonNames.length === 1 &&
    exploreParams.genes.length === 1 &&
    !isGeneList
  ) {
    showRelatedGenesIdeogram = true
    currentTaxon = exploreInfo.taxonNames[0]
    searchedGene = exploreParams.genes[0]
  }

  const isCorrelatedScatter = enabledTabs.includes('correlatedScatter')

  const annotationList = exploreInfo ? exploreInfo.annotationList : null
  // hide the cluster controls if we're on a genome/image tab, or if there aren't clusters to choose
  const showClusterControls = !['genome', 'infercnv-genome', 'images', 'geneListHeatmap'].includes(shownTab) &&
                                annotationList?.clusters?.length

  let hasSpatialGroups = false
  if (exploreInfo) {
    hasSpatialGroups = exploreInfo.spatialGroups.length > 0
  }

  const shownAnnotation = getShownAnnotation(exploreParamsWithDefaults.annotation, annotationList)

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

  /** handler for when the user selects points in a plotly scatter graph */
  function plotPointsSelected(points) {
    log('select:scatter:cells')
    setCurrentPointsSelected(points)
  }

  /** Handle clicks on "View Options" toggler element */
  function toggleViewOptions() {
    setShowViewOptionsControls(!showViewOptionsControls)
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
      exploreParamsWithDefaults.genes.length &&
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
      <div className="row">
        <div className="col-md-5">
          <div className="flexbox">
            <StudyGeneField genes={exploreParams.genes}
              searchGenes={searchGenes}
              allGenes={exploreInfo ? exploreInfo.uniqueGenes : []}
              isLoading={!exploreInfo}
              speciesList={exploreInfo ? exploreInfo.taxonNames : []}/>
            { // show if this is gene search || gene list
              (isGene || isGeneList || hasIdeogramOutputs) &&
                <OverlayTrigger placement='top' overlay={
                  <Tooltip id='back-to-cluster-view'>{'Return to cluster view'}</Tooltip>
                }>
                  <button className="action fa-lg"
                    onClick={() => searchGenes([])}>
                    <FontAwesomeIcon icon={faArrowLeft}/>
                  </button>
                </OverlayTrigger>
            }
          </div>
        </div>
        <div className="col-md-4 col-md-offset-1">
          <ul className="nav nav-tabs" role="tablist" data-analytics-name="explore-default">
            { enabledTabs.map(tabKey => {
              const label = tabList.find(({ key }) => key === tabKey).label
              return (
                <li key={tabKey}
                  role="presentation"
                  className={`study-nav ${tabKey === shownTab ? 'active' : ''} ${tabKey}-tab-anchor`}>
                  <a onClick={() => updateExploreParams({ tab: tabKey })}>{label}</a>
                </li>
              )
            })}
          </ul>
        </div>
      </div>

      <div className="row explore-tab-content">
        <div className={showViewOptionsControls ? 'col-md-10' : 'col-md-12'}>
          <div className="explore-plot-tab-content row">
            { showRelatedGenesIdeogram &&
              <RelatedGenesIdeogram
                gene={searchedGene}
                taxon={currentTaxon}
                target={`.${plotContainerClass}`}
                genesInScope={exploreInfo.uniqueGenes}
                searchGenes={searchGenes}
                speciesList={exploreInfo.taxonNames}
              />
            }
            { !showViewOptionsControls &&
              <button className="action view-options-toggle view-options-toggle-on"
                onClick={toggleViewOptions}
                data-analytics-name="view-options-show">
                OPTIONS <FontAwesomeIcon className="fa-lg" icon={faCog}/>
              </button>
            }
            { enabledTabs.includes('annotatedScatter') &&
              <div className={shownTab === 'annotatedScatter' ? '' : 'hidden'}>
                <ScatterPlot
                  studyAccession={studyAccession}
                  {...exploreParamsWithDefaults}
                  isAnnotatedScatter={true}
                  dimensionProps={{
                    numColumns: 1,
                    numRows: exploreParamsWithDefaults?.spatialGroups.length ? 2 : 1,
                    showRelatedGenesIdeogram,
                    showViewOptionsControls
                  }}
                  isCellSelecting={isCellSelecting}
                  plotPointsSelected={plotPointsSelected}
                  countsByLabel={countsByLabel}
                  setCountsByLabel={setCountsByLabel}
                />
              </div>
            }
            { enabledTabs.includes('correlatedScatter') &&
              <div className={shownTab === 'correlatedScatter' ? '' : 'hidden'}>
                <ScatterPlot
                  studyAccession={studyAccession}
                  {...exploreParamsWithDefaults}
                  isCorrelatedScatter={true}
                  dimensionProps={{
                    numColumns: 1,
                    numRows: 1
                  }}
                  isCellSelecting={isCellSelecting}
                  plotPointsSelected={plotPointsSelected}
                  countsByLabel={countsByLabel}
                  setCountsByLabel={setCountsByLabel}
                />
              </div>
            }
            { enabledTabs.includes('scatter') &&
              <div className={shownTab === 'scatter' ? '' : 'hidden'}>
                <ScatterTab
                  {...{
                    studyAccession,
                    exploreParamsWithDefaults,
                    updateExploreParamsWithDefaults: updateExploreParams,
                    exploreInfo,
                    isGeneList,
                    isGene,
                    isMultiGene,
                    isCellSelecting,
                    isCorrelatedScatter,
                    plotPointsSelected,
                    showRelatedGenesIdeogram,
                    showViewOptionsControls,
                    scatterColor: exploreParamsWithDefaults.scatterColor,
                    countsByLabel,
                    setCountsByLabel,
                    dataCache
                  }}/>
              </div>
            }
            { enabledTabs.includes('distribution') &&
              <div className={shownTab === 'distribution' ? '' : 'hidden'}>
                <StudyViolinPlot
                  studyAccession={studyAccession}
                  updateDistributionPlot={distributionPlot => updateExploreParams({ distributionPlot }, false)}
                  dimensions={getPlotDimensions({
                    showRelatedGenesIdeogram, showViewOptionsControls
                  })}
                  {...exploreParams}/>
              </div>
            }
            { enabledTabs.includes('dotplot') &&
              <div className={shownTab === 'dotplot' ? '' : 'hidden'}>
                <DotPlot
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  annotationValues={getAnnotationValues(
                     exploreParamsWithDefaults?.annotation,
                     exploreParamsWithDefaults?.annotationList?.annotations
                  )}
                  dimensions={getPlotDimensions({ showViewOptionsControls })}
                />
              </div>
            }
            { enabledTabs.includes('heatmap') &&
              <div className={shownTab === 'heatmap' ? '' : 'hidden'}>
                <Heatmap
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  dimensions={getPlotDimensions({ showViewOptionsControls })}
                />
              </div>
            }
            { enabledTabs.includes('geneListHeatmap') &&
              <div className={shownTab === 'geneListHeatmap' ? '' : 'hidden'}>
                <GeneListHeatmap
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  geneLists={exploreInfo.geneLists}
                  dimensions={getPlotDimensions({ showViewOptionsControls })}
                />
              </div>
            }
            { enabledTabs.includes('genome') &&
              <div className={shownTab === 'genome' ? '' : 'hidden'}>
                <GenomeView
                  studyAccession={studyAccession}
                  bamFileName={exploreParams.bamFileName}
                  uniqueGenes={exploreInfo.uniqueGenes}
                  isVisible={shownTab === 'genome'}
                  updateExploreParams={updateExploreParams}
                />
              </div>
            }
            { enabledTabs.includes('infercnv-genome') &&
            <div className={shownTab === 'infercnv-genome' ? '' : 'hidden'}>
              <InferCNVIdeogram
                studyAccession={studyAccession}
                ideogramFileId={exploreParams?.ideogramFileId}
                inferCNVIdeogramFiles={exploreInfo.inferCNVIdeogramFiles}
                showViewOptionsControls={showViewOptionsControls}
              />
            </div>
            }
            { enabledTabs.includes('images') &&
              <div className={shownTab === 'images' ? '' : 'hidden'}>
                <ImageTab
                  studyAccession={studyAccession}
                  imageFiles={exploreInfo.imageFiles}
                  bucketName={exploreInfo.bucketId}
                  isCellSelecting={isCellSelecting}
                  isVisible={shownTab === 'images'}
                  getPlotDimensions={getPlotDimensions}
                  exploreParams={exploreParams}
                  plotPointsSelected={plotPointsSelected}
                />
              </div>
            }
            { enabledTabs.includes('loading') &&
              <div className={shownTab === 'loading' ? '' : 'hidden'}>
                <LoadingSpinner testId="explore-spinner"/>
              </div>
            }
          </div>
        </div>
        <div className={showViewOptionsControls ? 'col-md-2 ' : 'hidden'}>
          <div className="view-options-toggle">
            {!showDifferentialExpressionPanel && !showUpstreamDifferentialExpressionPanel &&
              <>
                <FontAwesomeIcon className="fa-lg" icon={faCog}/> OPTIONS
                <button className="action"
                  onClick={toggleViewOptions}
                  title="Hide options"
                  data-analytics-name="view-options-hide">
                  <FontAwesomeIcon className="fa-lg" icon={faTimes}/>
                </button>
              </>
            }
            {(showDifferentialExpressionPanel || showUpstreamDifferentialExpressionPanel) &&
              <DifferentialExpressionPanelHeader
                setDeGenes={setDeGenes}
                setDeGroup={setDeGroup}
                setShowDifferentialExpressionPanel={setShowDifferentialExpressionPanel}
                setShowUpstreamDifferentialExpressionPanel={setShowUpstreamDifferentialExpressionPanel}
                isUpstream={showUpstreamDifferentialExpressionPanel}
                cluster={exploreParamsWithDefaults.cluster}
                annotation={shownAnnotation}
              />
            }
          </div>

          {!showDifferentialExpressionPanel && !showUpstreamDifferentialExpressionPanel &&
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
                          } else if (studyHasDe) {
                            setShowUpstreamDifferentialExpressionPanel(true)
                          }
                        }}
                      >Differential expression</button>
                      <DifferentialExpressionModal />
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
              { exploreParams.genes.length > 1 && !['genome', 'infercnv-genome'].includes(shownTab) &&
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
            <button className="action"
              onClick={clearExploreParams}
              title="Reset all view options"
              data-analytics-name="explore-view-options-reset">
              <FontAwesomeIcon icon={faUndo}/> Reset view
            </button>
            <button onClick={() => copyLink(routerLocation)}
              className="action"
              data-toggle="tooltip"
              title="Copy a link to this visualization to the clipboard">
              <FontAwesomeIcon icon={faLink}/> Get link
            </button>
          </>
          }
          {showDifferentialExpressionPanel && countsByLabel && annotHasDe &&
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
              countsByLabel={countsByLabel}
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
      </div>
    </>
  )
}

/**
  * return an array of the tab names that should be shown, given the exploreParams and exploreInfo
  * (note that the export is for test availability -- this funtion is not intended to be used elsewhere
  */
export function getEnabledTabs(exploreInfo, exploreParams) {
  const isGeneList = !!exploreParams.geneList
  const numGenes = exploreParams?.genes?.length
  const isMultiGene = numGenes > 1
  const isGene = exploreParams?.genes?.length > 0
  const isConsensus = !!exploreParams.consensus
  const hasClusters = exploreInfo && exploreInfo.clusterGroupNames.length > 0
  const hasSpatialGroups = exploreParams.spatialGroups?.length > 0
  const hasGenomeFiles = exploreInfo && exploreInfo?.bamBundleList?.length > 0
  const hasIdeogramOutputs = !!exploreInfo?.inferCNVIdeogramFiles
  const hasImages = exploreInfo?.imageFiles?.length > 0

  let enabledTabs = []
  if (isGeneList) {
    enabledTabs = ['geneListHeatmap']
  } else if (isGene) {
    if (isMultiGene) {
      if (isConsensus) {
        if (exploreParams.annotation.type === 'numeric') {
          enabledTabs = ['annotatedScatter', 'dotplot', 'heatmap']
        } else {
          enabledTabs = ['scatter', 'distribution', 'dotplot']
        }
      } else if (hasSpatialGroups) {
        enabledTabs = ['scatter', 'dotplot', 'heatmap']
      } else {
        enabledTabs = ['dotplot', 'heatmap']
        if (numGenes === 2) {
          enabledTabs = ['correlatedScatter', 'dotplot', 'heatmap']
        }
      }
    } else if (exploreParams.annotation.type === 'numeric') {
      enabledTabs = ['annotatedScatter', 'scatter']
    } else {
      enabledTabs = ['scatter', 'distribution']
    }
  } else if (hasClusters) {
    enabledTabs = ['scatter']
  }
  if (hasGenomeFiles) {
    enabledTabs.push('genome')
  }
  if (hasIdeogramOutputs) {
    enabledTabs.push('infercnv-genome')
  }
  if (hasImages) {
    enabledTabs.push('images')
  }

  if (!exploreInfo) {
    enabledTabs = ['loading']
  }

  return { enabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs }
}
