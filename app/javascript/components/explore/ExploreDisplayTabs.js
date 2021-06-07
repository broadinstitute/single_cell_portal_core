import React, { useState } from 'react'
import _clone from 'lodash/clone'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLink, faArrowLeft, faCog, faTimes, faDna, faUndo } from '@fortawesome/free-solid-svg-icons'


import StudyGeneField from './StudyGeneField'
import ClusterSelector from 'components/visualization/controls/ClusterSelector'
import AnnotationSelector from 'components/visualization/controls/AnnotationSelector'
import SubsampleSelector from 'components/visualization/controls/SubsampleSelector'
import { ExploreConsensusSelector } from 'components/visualization/controls/ConsensusSelector'
import SpatialSelector from 'components/visualization/controls/SpatialSelector'
import CreateAnnotation from 'components/visualization/controls/CreateAnnotation'
import PlotDisplayControls from 'components/visualization/PlotDisplayControls'
import GeneListSelector from 'components/visualization/controls/GeneListSelector'
import InferCNVIdeogramSelector from 'components/visualization/controls/InferCNVIdeogramSelector'
import { createCache } from './plot-data-cache'
import ScatterTab from './ScatterTab'
import ScatterPlot from 'components/visualization/ScatterPlot'
import StudyViolinPlot from 'components/visualization/StudyViolinPlot'
import DotPlot from 'components/visualization/DotPlot'
import Heatmap from 'components/visualization/Heatmap'
import GenomeView from './GenomeView'
import { getAnnotationValues, getDefaultSpatialGroupsForCluster } from 'lib/cluster-utils'
import RelatedGenesIdeogram from 'components/visualization/RelatedGenesIdeogram'
import InferCNVIdeogram from 'components/visualization/InferCNVIdeogram'
import useResizeEffect from 'hooks/useResizeEffect'
import { log } from 'lib/metrics-api'


const tabList = [
  { key: 'loading', label: 'loading...' },
  { key: 'scatter', label: 'Scatter' },
  { key: 'annotatedScatter', label: 'Annotated Scatter' },
  { key: 'distribution', label: 'Distribution' },
  { key: 'dotplot', label: 'Dot Plot' },
  { key: 'heatmap', label: 'Heatmap' },
  { key: 'spatial', label: 'Spatial' },
  { key: 'genome', label: 'Genome' },
  { key: 'infercnv-genome', label: 'Genome (inferCNV)' }
]

const ideogramHeight = 140

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
  const plotContainerClass = 'explore-plot-tab-content'
  const {
    enabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs
  } = getEnabledTabs(exploreInfo, exploreParams)

  // exploreParams object without genes specified, to pass to cluster comparison plots
  const referencePlotDataParams = _clone(exploreParams)
  referencePlotDataParams.genes = []

  /** helper function so that StudyGeneField doesn't have to see the full exploreParams object */
  function searchGenes(genes) {
    // also unset any selected gene lists or ideogram files
    updateExploreParams({ genes, geneList: '', ideogramFileId: '' })
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
  const showClusterControls = !(['genome', 'infercnv-genome'].includes(shownTab))

  const annotationList = exploreInfo ? exploreInfo.annotationList : null

  let hasSpatialGroups = false
  if (exploreInfo) {
    hasSpatialGroups = exploreInfo.spatialGroups.length > 0
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
    updateExploreParams(updateParams)
  }

  /** handles gene list selection */
  function updateGeneList(geneList) {
    updateExploreParams({ geneList })
  }

  /** handles updating inferCNV/ideogram selection */
  function updateInferCNVIdeogramFile(annotationFile) {
    updateExploreParams({ ideogramFileId: annotationFile, tab: 'infercnv-genome' })
  }


  /** Get width and height available for plot components, since they may be first rendered hidden */
  function getPlotDimensions({
    isTwoColumn=false,
    isMultiRow=false,
    verticalPad=250,
    horizontalPad=80,
    hasTitle=false
  }) {
    // Get width, and account for expanding "View Options" after page load
    let baseWidth = $(window).width()
    if (showViewOptionsControls) {
      baseWidth = Math.round(baseWidth * 10 / 12)
    }
    let width = (baseWidth - horizontalPad) / (isTwoColumn ? 2 : 1)

    // Get height
    // Height of screen viewport, minus fixed-height elements above gallery
    let galleryHeight = $(window).height() - verticalPad
    if (showRelatedGenesIdeogram) {
      galleryHeight -= ideogramHeight
    }
    if (hasTitle) {
      galleryHeight -= 20
    }
    let height = galleryHeight
    if (isMultiRow) {
      // Fill as much gallery height as possible, but show tip of next row
      // as an affordance that the gallery is vertically scrollable.
      const secondRowTipHeight = 70
      height = height - secondRowTipHeight
    }
    // ensure aspect ratio isn't too distorted
    if (height > width * 1.3) {
      height = Math.round(width * 1.3)
    }

    // Ensure plots aren't too small.
    // This was needed as of 2020-12-14 to avoid a Plotly error in single-gene
    // view: "Something went wrong with axes scaling"
    height = Math.max(height, 200)
    width = Math.max(width, 200)

    return { width, height }
  }

  /** on window resize call setRenderForcer, which is just trivial state to ensure a re-render
   * ensuring that the plots get passed fresh dimensions */
  useResizeEffect(() => {
    setRenderForcer({})
  }, 300)

  console.log('in ExploreDisplayTabs.js, exploreInfo, exploreParams', JSON.stringify(exploreInfo), exploreParams)

  return (
    <>
      <div className="row">
        <div className="col-md-5">
          <div className="flexbox">
            <StudyGeneField genes={exploreParams.genes}
              searchGenes={searchGenes}
              allGenes={exploreInfo ? exploreInfo.uniqueGenes : []}
              speciesList={exploreInfo ? exploreInfo.taxonNames : []}/>
            { /* show if this is gene search || gene list */ }
            <button className={isGene || isGeneList || hasIdeogramOutputs ? 'action fa-lg' : 'hidden'}
              onClick={() => searchGenes([])}
              title="Return to cluster view"
              data-toggle="tooltip"
              data-analytics-name="back-to-cluster-view">
              <FontAwesomeIcon icon={faArrowLeft}/>
            </button>
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
                height={ideogramHeight}
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
                  {...exploreParams}
                  isAnnotatedScatter={true}
                  dimensions={getPlotDimensions({
                    numColumns: 1,
                    numRows: exploreParams?.spatialGroups.length ? 2 : 1,
                    hasTitle: true,
                    showRelatedGenesIdeogram
                  })}
                  isCellSelecting={isCellSelecting}
                  plotPointsSelected={plotPointsSelected}
                />
              </div>
            }
            { enabledTabs.includes('scatter') &&
              <div className={shownTab === 'scatter' ? '' : 'hidden'}>
                <ScatterTab
                  {...{
                    studyAccession,
                    exploreParams,
                    updateExploreParams,
                    exploreInfo,
                    isGeneList,
                    isGene,
                    isMultiGene,
                    isCellSelecting,
                    plotPointsSelected,
                    getPlotDimensions,
                    dataCache
                  }}/>
              </div>
            }
            { enabledTabs.includes('distribution') &&
              <div className={shownTab === 'distribution' ? '' : 'hidden'}>
                <StudyViolinPlot
                  studyAccession={studyAccession}
                  updateDistributionPlot={distributionPlot => updateExploreParams({ distributionPlot }, false)}
                  dimensions={getPlotDimensions({})}
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
                  dimensions={getPlotDimensions({})}
                />
              </div>
            }
            { enabledTabs.includes('heatmap') &&
              <div className={shownTab === 'heatmap' ? '' : 'hidden'}>
                <Heatmap
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  dimensions={getPlotDimensions({})}/>
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
            { enabledTabs.includes('loading') &&
            <div className={shownTab === 'loading' ? '' : 'hidden'}>
              <FontAwesomeIcon icon={faDna} className="gene-load-spinner"/>
            </div>
            }
          </div>
        </div>
        <div className={showViewOptionsControls ? 'col-md-2 ' : 'hidden'}>
          <div className="view-options-toggle">
            <FontAwesomeIcon className="fa-lg" icon={faCog}/> OPTIONS
            <button className="action"
              onClick={toggleViewOptions}
              title="Hide options"
              data-analytics-name="view-options-hide">
              <FontAwesomeIcon className="fa-lg" icon={faTimes}/>
            </button>
          </div>
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
                annotation={exploreParamsWithDefaults.annotation}
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
            updateExploreParams={updateExploreParams}/>
          <button className="action"
            onClick={clearExploreParams}
            title="reset all view options"
            data-analytics-name="explore-view-options-reset">
            <FontAwesomeIcon icon={faUndo}/> Reset view
          </button>
          <br/><br/>
          <button onClick={() => copyLink(routerLocation)}
            className="action"
            data-toggle="tooltip"
            title="copy a link to this visualization to the clipboard">
            <FontAwesomeIcon icon={faLink}/> Get link
          </button>
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
  const isMultiGene = exploreParams?.genes?.length > 1
  const isGene = exploreParams?.genes?.length > 0
  const isConsensus = !!exploreParams.consensus
  const hasClusters = exploreInfo && exploreInfo.clusterGroupNames.length > 0
  const hasSpatialGroups = exploreParams.spatialGroups?.length > 0
  const hasGenomeFiles = exploreInfo && exploreInfo?.bamBundleList?.length > 0
  const hasIdeogramOutputs = !!exploreInfo?.inferCNVIdeogramFiles

  let enabledTabs = []
  if (isGeneList) {
    enabledTabs = ['heatmap']
  } else if (isGene) {
    if (isMultiGene) {
      if (isConsensus) {
        enabledTabs = ['scatter', 'distribution', 'dotplot']
      } else if (hasSpatialGroups) {
        enabledTabs = ['scatter', 'dotplot', 'heatmap']
      } else {
        enabledTabs = ['dotplot', 'heatmap']
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

  if (!exploreInfo) {
    enabledTabs = ['loading']
  }
  return { enabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs }
}
