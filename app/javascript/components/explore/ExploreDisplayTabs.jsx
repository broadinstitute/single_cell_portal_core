import React, { useState, useEffect } from 'react'
import _clone from 'lodash/clone'
import _isEqual from 'lodash/isEqual'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faArrowLeft, faEye } from '@fortawesome/free-solid-svg-icons'

import StudyGeneField from './StudyGeneField'
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
import { getAnnotationValues, getShownAnnotation } from '~/lib/cluster-utils'
import RelatedGenesIdeogram from '~/components/visualization/RelatedGenesIdeogram'
import InferCNVIdeogram from '~/components/visualization/InferCNVIdeogram'
import useResizeEffect from '~/hooks/useResizeEffect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { log } from '~/lib/metrics-api'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import ExploreDisplayPanelManager from './ExploreDisplayPanelManager'
import OverlayTrigger from 'react-bootstrap/lib/OverlayTrigger'
import Tooltip from 'react-bootstrap/lib/Tooltip'
import PlotTabs from './PlotTabs'
import { initCellFaceting, filterCells } from '~/lib/cell-faceting'

/** Get the selected clustering and annotation, or their defaults */
export function getSelectedClusterAndAnnot(exploreInfo, exploreParams) {
  if (!exploreInfo) {return [null, null]}
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

/** Handle switching to a new clustering that has annotations (i.e., facets) not in previous clustering */
export function handleClusterSwitchForFiltering(cellFilteringSelection, newCellFaceting, setCellFilteringSelection) {
  if (cellFilteringSelection) {
    const existingSelectionFacets = Object.keys(cellFilteringSelection)
    const updatedSelectionFacets =
      newCellFaceting.facets.filter(
        nf => !nf.isSelectedAnnotation && !existingSelectionFacets.includes(nf.annotation) && 'groups' in nf
      )
    if (updatedSelectionFacets.length > 0) {
      updatedSelectionFacets.forEach(uf => cellFilteringSelection[uf.annotation] = uf.groups)
    }

    setCellFilteringSelection(cellFilteringSelection)
  }
}

/** wrapper function with error handling/state setting for retrieving cell facet data */
function getCellFacetingData(cluster, annotation, setterFunctions, context, prevCellFaceting) {
  const [
    setCellFilteringSelection,
    setClusterCanFilter,
    setFilterErrorText,
    setCellFilterCounts,
    setCellFaceting,
    updateFilteredCells
  ] = setterFunctions

  const {
    exploreParams,
    exploreInfo,
    studyAccession,
    cellFilteringSelection
  } = context

  const showCellFiltering = getFeatureFlagsWithDefaults()?.show_cell_facet_filtering
  if (showCellFiltering) {
    const allAnnots = exploreInfo?.annotationList.annotations
    if (allAnnots && allAnnots.length > 0) {
      if (!prevCellFaceting?.isFullyLoaded) {
        initCellFaceting(
          cluster, annotation, studyAccession, allAnnots, prevCellFaceting
        ).then(newCellFaceting => {
          const initSelection = {}
          if (!cellFilteringSelection) {
            newCellFaceting.facets.filter(f => !f.isSelectedAnnotation).forEach(facet => {
              initSelection[facet.annotation] = facet.defaultSelection
            })

            setCellFilteringSelection(initSelection)
          }

          // Handle switching to a new clustering that has annotations (i.e., facets) not in previous clustering
          handleClusterSwitchForFiltering(cellFilteringSelection, newCellFaceting, setCellFilteringSelection)

          setClusterCanFilter(true)
          setFilterErrorText('')

          let selectionFromUrl = {}
          if (exploreParams?.facets && exploreParams.facets !== undefined) {
            const thisSelection = cellFilteringSelection ?? initSelection
            selectionFromUrl = parseFacetsParam(
              thisSelection, exploreParams.facets
            )
          }
          if (!_isEqual(cellFilteringSelection, selectionFromUrl)) {
            setCellFilterCounts(newCellFaceting.filterCounts)
            setCellFaceting(newCellFaceting)
          }


          // The cell filtering UI is initialized in batches of 5 facets
          // This recursively loads the next 5 facets until faceting is fully loaded.
          getCellFacetingData(cluster, annotation, setterFunctions, context, newCellFaceting)
        }).catch(error => {
        // NOTE: these 'errors' are in fact handled corner cases where faceting data isn't present for various reasons
        // as such, they don't need to be reported to Sentry/Mixpanel, only conveyed to the user
        // example: 400 (Bad Request): Clustering is not indexed, Cannot use numeric annotations for facets, or
        // 404 (Not Found) Cluster not found
        // see app/controllers/api/v1/visualization/annotations_controller.rb#facets for more information
          setClusterCanFilter(false)
          setFilterErrorText(error.message)
          console.error(error) // Show trace in console; retains debuggability if actual error
        })
      } else {
        if (exploreParams?.facets && exploreParams.facets !== undefined) {
          let selection = {}
          if (!cellFilteringSelection) {
            prevCellFaceting.facets.forEach(facet => {
              selection[facet.annotation] = facet.groups
            })
          } else {
            selection = cellFilteringSelection
          }

          const selectionFromUrl = parseFacetsParam(
            selection, exploreParams.facets
          )

          if (!_isEqual(selection, selectionFromUrl)) {
            updateFilteredCells(selectionFromUrl, prevCellFaceting)
          }
        }
      }
    }
  }
}

/** Get `facets` parameter value, for cell filtering */
function getFacetsParam(initFacets, selection) {
  const minimalSelection = {}

  const initSelection = {}
  initFacets.filter(f => !f.isSelectedAnnotation).forEach(facet => {
    // if (facet.type === 'group') {
    initSelection[facet.annotation] = facet.defaultSelection
    // }
  })

  const innerParams = []
  Object.entries(initSelection).forEach(([facet, filters]) => {
    filters.forEach(filter => {
      // Unlike `selection`, which specifies all filters that are selected
      // (i.e., checked and not applied), the `facets` parameter species only
      // filters that are _not_ selected, i.e. they're unchecked and applied.
      //
      // This makes the `facets` parameter much clearer.
      if (facet.type === 'group' && !selection[facet].includes(filter)) {
        if (facet in minimalSelection) {
          minimalSelection[facet].push(filter)
        } else {
          minimalSelection[facet] = [filter]
        }
      }
    })
  })

  Object.entries(minimalSelection).forEach(([facet, filters]) => {
    const innerParam = `${facet}:${filters.join('|')}`
    innerParams.push(innerParam)
  })

  const facetParams = innerParams.join(';')
  return facetParams
}

/** Parse `facets` URL parameter into cell filtering selection object */
function parseFacetsParam(initFacets, facetsParam) {
  const selection = {}

  // Convert the `facets` parameter value, which is a string,
  // into an object that has the same shape as `selections`
  const facets = {}
  const innerParams = facetsParam.split(';')
  innerParams.forEach(innerParam => {
    const [facet, rawFilters] = innerParam.split(':')
    const filters = rawFilters.split('|')
    facets[facet] = filters
  })

  // Take the complement of the minimal `facets` object, transforming
  // it into the more verbose `selection` object which specifies filters
  // that are _not_ applied.
  Object.entries(initFacets).forEach(([facet, filters]) => {
    filters.forEach(filter => {
      if (!facets[facet]?.includes(filter)) {
        if (facet in selection) {
          selection[facet].push(filter)
        } else {
          selection[facet] = [filter]
        }
      }
    })
  })

  return selection
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

  // morpheus JSON data
  const [morpheusData, setMorpheusData] = useState(null)
  // Differential expression settings
  const hasPairwiseDe = getHasComparisonDe(exploreInfo, exploreParams, 'pairwise')

  const [, setShowDeGroupPicker] = useState(false)
  const [deGenes, setDeGenes] = useState(null)
  const [showDifferentialExpressionPanel, setShowDifferentialExpressionPanel] = useState(deGenes !== null)
  const [showUpstreamDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel] = useState(deGenes !== null)

  let initialPanel = 'options'
  if (showDifferentialExpressionPanel || showUpstreamDifferentialExpressionPanel) {
    initialPanel = 'differential-expression'
  } else if (exploreParams.facets !== '') {
    initialPanel = 'cell-filtering'
  }
  const [panelToShow, setPanelToShow] = useState(initialPanel)

  // Hash of trace label names to the number of points in that trace
  const [countsByLabel, setCountsByLabel] = useState(null)
  const showDifferentialExpressionTable = (showViewOptionsControls && deGenes !== null)
  const plotContainerClass = 'explore-plot-tab-content'

  const [cellFaceting, setCellFaceting] = useState(null)
  const [filteredCells, setFilteredCells] = useState(null)
  const [cellFilterCounts, setCellFilterCounts] = useState(null)

  const [cellFilteringSelection, setCellFilteringSelection] = useState(null)

  // flow/error handling for cell filtering
  const [clusterCanFilter, setClusterCanFilter] = useState(true)
  const [filterErrorText, setFilterErrorText] = useState(null)

  const {
    enabledTabs, disabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs
  } = getEnabledTabs(exploreInfo, exploreParamsWithDefaults, cellFaceting)

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


  // If clustering or annotation changes, then update facets shown for cell filtering
  useEffect(() => {
    if (!exploreInfo) {return}
    if (exploreInfo.skipFetchFacets) {
      // The loadStudyData in ExploreView updates exploreParams _twice_ upon
      // loading the page.  To avoid doubling requests to the `/facets` API
      // endpoint, this special `skipFetchFacets` prop is set to true in the
      // 2nd upstream update.  This block _skips_ that 2nd volley of /facets
      // requests triggered by that pageload-time double state update
      // in loadStudyData.
      exploreInfo.skipFetchFacets = false
      return
    }
    const [newCluster, newAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)

    const paramCluster = exploreParams.cluster
    const paramAnnot = exploreParams.annotation

    if (
      filteredCells &&
      (
        (paramCluster === '' && paramAnnot.name === '') ||
        (paramCluster === newCluster && _isEqual(paramAnnot, newAnnot))
      )
    ) {
      // We've fully loaded facets,
      // and cluster and annotation are the default or not actually changed,
      // but another parameter has changed.
      // We only need to get cell faceting data when either clustering or
      // annotation has changed, so skip unless we detect a change.
      return
    }

    const setterFunctions = [
      setCellFilteringSelection,
      setClusterCanFilter,
      setFilterErrorText,
      setCellFilterCounts,
      setCellFaceting,
      updateFilteredCells
    ]
    const context = {
      exploreParams,
      exploreInfo,
      studyAccession,
      cellFilteringSelection
    }
    getCellFacetingData(newCluster, newAnnot, setterFunctions, context)
  }, [exploreParams?.cluster, exploreParams?.annotation])


  /** Update filtered cells to only those that match annotation group value filter selections */
  function updateFilteredCells(selection, overrideCellFaceting) {
    const thisCellFaceting = overrideCellFaceting ?? cellFaceting
    if (!thisCellFaceting) {return}
    if (!selection) {
      setFilteredCells(null)
      return
    }

    const cellsByFacet = thisCellFaceting.cellsByFacet
    const initFacets = thisCellFaceting.facets
    const filterableCells = thisCellFaceting.filterableCells
    const rawFacets = thisCellFaceting.rawFacets.facets

    // Filter cells by selection (i.e., selected facets and filters)
    const [newFilteredCells, newFilterCounts] = filterCells(
      selection, cellsByFacet, initFacets, filterableCells, rawFacets
    )

    // Update UI
    setFilteredCells(newFilteredCells)
    setCellFilterCounts(newFilterCounts)
    setCellFilteringSelection(selection)

    if (!overrideCellFaceting) {
      const facetsParam = getFacetsParam(initFacets, selection)
      updateExploreParams({ facets: facetsParam })
    }
  }

  // Below line is worth keeping, but only uncomment to debug in development
  window.SCP.updateFilteredCells = updateFilteredCells

  /** handler for when the user selects points in a plotly scatter graph */
  function plotPointsSelected(points) {
    log('select:scatter:cells')
    setCurrentPointsSelected(points)
  }
  /** Handle clicks on "View Options" toggler element */
  function toggleViewOptions() {
    setShowViewOptionsControls(!showViewOptionsControls)
  }

  /** toggle between the panels for DE, Facet Filtering and Default
   * needed at this level for choosing style for panel
  */
  function togglePanel(panelOption) {
    setPanelToShow(panelOption)
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

  /** Get widths for main (plots) and side (options, DE, or FF) panels, for current Explore state */
  function getPanelWidths() {
    let main
    let side
    if (showViewOptionsControls) {
      if (
        (deGenes !== null) ||
          (hasPairwiseDe && (showDifferentialExpressionPanel || showUpstreamDifferentialExpressionPanel))
      ) {
        // DE table is shown, or pairwise DE is available.  Least horizontal space for plots.
        main = 'col-md-9'
        side = 'col-md-3 right-panel'
      } else if (panelToShow === 'cell-filtering') {
        main = 'col-md-10-5'
        side = 'col-md-2-5 right-panel'
      } else {
        // Default state, when side panel is "Options" and not collapsed
        main = 'col-md-10'
        // only set options-bg if we're outside the DE UX

        side = panelToShow === 'options' ? 'col-md-2 options-bg right-panel' : 'col-md-2 right-panel'
      }
    } else {
      // When options panel is collapsed.  Maximize horizontal space for plots.
      main = 'col-md-12'
      side = 'hidden'
    }
    return { main, side }
  }

  console.log('cellFilteringSelection')
  console.log(cellFilteringSelection)

  return (
    <>
      {/* Render top content for Explore view, i.e. gene search box and plot tabs */}
      <div className="row position-forward">
        <div className="col-md-5">
          <div className="flexbox">
            <StudyGeneField genes={exploreParams.genes}
              searchGenes={searchGenes}
              allGenes={exploreInfo ? exploreInfo.uniqueGenes : []}
              isLoading={!exploreInfo}
              speciesList={exploreInfo ? exploreInfo.taxonNames : []}/>
            { // show if this is gene search || gene list
              (isGene || isGeneList || hasIdeogramOutputs) &&
                <OverlayTrigger placement="top" overlay={
                  <Tooltip id="back-to-cluster-view">{'Return to cluster view'}</Tooltip>
                }>
                  <button className="action fa-lg"
                    aria-label="Back arrow"
                    onClick={() => searchGenes([])}>
                    <FontAwesomeIcon icon={faArrowLeft}/>
                  </button>
                </OverlayTrigger>
            }
          </div>
        </div>
        <PlotTabs
          shownTab={shownTab}
          enabledTabs={enabledTabs}
          disabledTabs={disabledTabs}
          updateExploreParams={updateExploreParams}
        />
      </div>

      {/* Render plots for the given Explore view state */}
      <div className="row explore-tab-content">
        <div className={getPanelWidths().main}>
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
                  updateExploreParams={updateExploreParams}
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
                  updateExploreParams={updateExploreParams}
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
                    showDifferentialExpressionTable,
                    scatterColor: exploreParamsWithDefaults.scatterColor,
                    countsByLabel,
                    setCountsByLabel,
                    dataCache,
                    filteredCells,
                    cellFilteringSelection
                  }}/>
              </div>
            }
            { enabledTabs.includes('distribution') &&
              <div className={shownTab === 'distribution' ? '' : 'hidden'}>
                <StudyViolinPlot
                  studyAccession={studyAccession}
                  updateDistributionPlot={distributionPlot => updateExploreParams({ distributionPlot }, false)}
                  dimensions={getPlotDimensions({
                    showRelatedGenesIdeogram, showViewOptionsControls, showDifferentialExpressionTable
                  })}
                  cellFaceting={cellFaceting}
                  filteredCells={filteredCells}
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
                  setMorpheusData={setMorpheusData}
                  dimensions={getPlotDimensions({ showViewOptionsControls, showDifferentialExpressionTable })}
                />
              </div>
            }
            { enabledTabs.includes('heatmap') &&
              <div className={shownTab === 'heatmap' ? '' : 'hidden'}>
                <Heatmap
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  morpheusData={morpheusData}
                  dimensions={getPlotDimensions({ showViewOptionsControls, showDifferentialExpressionTable })}
                />
              </div>
            }
            { enabledTabs.includes('geneListHeatmap') &&
              <div className={shownTab === 'geneListHeatmap' ? '' : 'hidden'}>
                <GeneListHeatmap
                  studyAccession={studyAccession}
                  {... exploreParamsWithDefaults}
                  geneLists={exploreInfo.geneLists}
                  dimensions={getPlotDimensions({ showViewOptionsControls, showDifferentialExpressionTable })}
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
            { enabledTabs.includes('loading') &&
              <div className={shownTab === 'loading' ? '' : 'hidden'}>
                <LoadingSpinner testId="explore-spinner"/>
              </div>
            }
          </div>
        </div>
        { !showViewOptionsControls &&
              <button className={showDifferentialExpressionPanel ?
                'action view-options-toggle view-options-toggle-on' :
                'action view-options-toggle view-options-toggle-on minified-options'
              }
              onClick={toggleViewOptions}
              data-analytics-name="view-options-show">
                <FontAwesomeIcon className="fa-lg" icon={faEye}/>
              </button>
        }
        <div className={getPanelWidths().side}>
          <ExploreDisplayPanelManager
            studyAccession={studyAccession}
            exploreInfo={exploreInfo}
            setExploreInfo={setExploreInfo}
            exploreParams={exploreParams}
            updateExploreParams={updateExploreParams}
            clearExploreParams={clearExploreParams}
            exploreParamsWithDefaults={exploreParamsWithDefaults}
            routerLocation={routerLocation}
            searchGenes={searchGenes}
            countsByLabel={countsByLabel}
            setShowUpstreamDifferentialExpressionPanel={setShowUpstreamDifferentialExpressionPanel}
            showDifferentialExpressionPanel={showDifferentialExpressionPanel}
            setShowDifferentialExpressionPanel={setShowDifferentialExpressionPanel}
            showUpstreamDifferentialExpressionPanel={showUpstreamDifferentialExpressionPanel}
            togglePanel={togglePanel}
            shownTab={shownTab}
            setIsCellSelecting={setIsCellSelecting}
            currentPointsSelected={currentPointsSelected}
            isCellSelecting={isCellSelecting}
            deGenes={deGenes}
            setDeGenes={setDeGenes}
            setShowDeGroupPicker={setShowDeGroupPicker}
            cellFaceting={cellFaceting}
            cellFilteringSelection={cellFilteringSelection}
            cellFilterCounts={cellFilterCounts}
            clusterCanFilter={clusterCanFilter}
            filterErrorText ={filterErrorText}
            updateFilteredCells={updateFilteredCells}
            panelToShow={panelToShow}
            toggleViewOptions={toggleViewOptions}
          />
        </div>
      </div>
    </>
  )
}

/**
  * return an array of the tab names that should be shown, given the exploreParams and exploreInfo
  * (note that the export is for test availability -- this funtion is not intended to be used elsewhere
  */
export function getEnabledTabs(exploreInfo, exploreParams, cellFaceting) {
  const isGeneList = !!exploreParams.geneList
  const numGenes = exploreParams?.genes?.length
  const isMultiGene = numGenes > 1
  const isGene = exploreParams?.genes?.length > 0
  const isConsensus = !!exploreParams.consensus
  const hasClusters = exploreInfo && exploreInfo.clusterGroupNames.length > 0
  const hasSpatialGroups = exploreParams.spatialGroups?.length > 0
  const hasGenomeFiles = exploreInfo && exploreInfo?.bamBundleList?.length > 0
  const hasIdeogramOutputs = !!exploreInfo?.inferCNVIdeogramFiles
  const isNumeric = exploreParams?.annotation?.type === 'numeric'

  let coreTabs = [
    'annotatedScatter', 'scatter',
    'distribution', 'correlatedScatter',
    'dotplot', 'heatmap'
  ]

  let enabledTabs = []

  if (isGeneList) {
    enabledTabs = ['geneListHeatmap']
  } else if (isGene) {
    if (isMultiGene) {
      if (isConsensus) {
        coreTabs = coreTabs.filter(tab => tab !== 'correlatedScatter') // omit for consensus
        if (isNumeric) {
          enabledTabs = ['annotatedScatter', 'dotplot', 'heatmap']
        } else {
          enabledTabs = ['scatter', 'distribution', 'dotplot']
          coreTabs = coreTabs.filter(tab => tab !== 'heatmap') // omit for consensus
        }
      } else if (hasSpatialGroups) {
        enabledTabs = ['scatter', 'dotplot', 'heatmap']
      } else {
        enabledTabs = ['dotplot', 'heatmap']
        if (numGenes === 2) {
          enabledTabs = ['correlatedScatter', 'dotplot', 'heatmap']
        }
      }
    } else if (isNumeric) {
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

  let disabledTabs = coreTabs.filter(tab => {
    return (
      !enabledTabs.includes(tab) && // Omit any enabled tabs
      !(!isNumeric && tab === 'annotatedScatter') // Omit "Annotated scatter" for group annotations
    )
  })

  if (
    !exploreInfo ||
    (exploreParams.facets !== '' && !cellFaceting?.isFullyLoaded)
  ) {
    enabledTabs = ['loading']
    disabledTabs = []
  }

  return { enabledTabs, disabledTabs, isGeneList, isGene, isMultiGene, hasIdeogramOutputs }
}
