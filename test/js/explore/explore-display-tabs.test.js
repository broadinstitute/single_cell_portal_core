

// mock various modules from genome tab as these aren't being used, and throw compilation errors from jest
jest.mock('components/explore/GenomeView', () => {
  return {
    igv: jest.fn(() => mockPromise)
  }
})

jest.mock('components/visualization/RelatedGenesIdeogram', () => {
  return {
    Ideogram: jest.fn(() => mockPromise)
  }
})

jest.mock('components/visualization/InferCNVIdeogram', () => {
  return {
    Ideogram: jest.fn(() => mockPromise)
  }
})

// Mock cell faceting functionality, as it's tested in /test/js/lib/cell-faceting.test.js
jest.mock('lib/cell-faceting', () => {
  return {
    initCellFaceting: jest.fn(() => new Promise(() => {}))
  }
})

import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import * as UserProvider from '~/providers/UserProvider'
import ExploreDisplayTabs, {
  getEnabledTabs, handleClusterSwitchForFiltering
} from 'components/explore/ExploreDisplayTabs'
import ExploreDisplayPanelManager from '~/components/explore/ExploreDisplayPanelManager'
import PlotTabs from 'components/explore/PlotTabs'
import {
  exploreInfo as exploreInfoDe,
  exploreParams as exploreParamsDe
} from './explore-tab-de-integration.test-data'
import '@testing-library/jest-dom/extend-expect'

// mock explore info from a study
const defaultExploreInfo = {
  cluster: 'foo',
  taxonNames: ['Homo sapiens'],
  inferCNVIdeogramFiles: null,
  bamBundleList: [],
  uniqueGenes: ['Agpat2', 'Apoe', 'Gad1', 'Gad2'],
  geneLists: [],
  annotationList: [],
  clusterGroupNames: ['foo', 'bar'],
  spatialGroupNames: [],
  spatialGroups: [],
  clusterPointAlpha: 1.0,
  facets: ''
}

describe('explore tabs are activated based on study info and parameters', () => {
  it('should show the loading tab while waiting for the explore info', async () => {
    const exploreInfo = null
    const exploreParams = {
      cluster: 'foo', // request params loading only a cluster
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      userSpecified: {
        annotation: true,
        cluster: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['loading'],
      disabledTabs: [],
      isGeneList: false,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable cluster tab', async () => {
    const exploreInfo = defaultExploreInfo
    const exploreParams = {
      cluster: 'foo', // request params loading only a cluster
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      userSpecified: {
        annotation: true,
        cluster: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['scatter'],
      disabledTabs: ['distribution', 'correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: false,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should handle numeric annotations in no-gene view', async () => {
    const exploreInfo = defaultExploreInfo
    const exploreParams = {
      cluster: 'foo', // request params loading only a cluster
      annotation: { name: 'bar', type: 'numeric', scope: 'study' },
      userSpecified: {
        annotation: true,
        cluster: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['scatter'],
      disabledTabs: ['annotatedScatter', 'distribution', 'correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: false,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should render disabled "Annotated scatter" tab', async () => {
    const { container } = render((
      <PlotTabs
        shownTab={'scatter'}
        enabledTabs={['scatter']}
        disabledTabs={['annotatedScatter', 'distribution', 'correlatedScatter', 'dotplot', 'heatmap']}
        updateExploreParams={function() {}}
        isNewExploreUX={true}
      />
    ))

    const deButton = container.querySelector('.annotatedScatter-tab-anchor')
    expect(deButton).toHaveTextContent('Annotated scatter')
  })

  it('should handle numeric annotations in 1-gene view', async () => {
    const exploreInfo = defaultExploreInfo
    const exploreParams = {
      cluster: 'foo', // request params loading only a cluster
      annotation: { name: 'bar', type: 'numeric', scope: 'study' },
      genes: ['Agpat2'],
      userSpecified: {
        annotation: true,
        cluster: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['annotatedScatter', 'scatter'],
      disabledTabs: ['distribution', 'correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: false,
      isGene: true,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should only enable cluster tab in default, 0-gene view', async () => {
    // mock exploreInfo from study
    const exploreInfo = {
      ...defaultExploreInfo,
      bamBundleList: [
        { 'name': 'sample1.bam', 'file_type': 'BAM' },
        { 'name': 'sample1.bam.bai', 'file_type': 'BAM Index' }
      ]
    }

    const exploreParams = {
      cluster: 'foo',
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      trackFileName: 'sample1.bam',
      userSpecified: {
        annotation: true,
        cluster: true,
        trackFileName: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['scatter'],
      disabledTabs: ['distribution', 'correlatedScatter', 'dotplot', 'heatmap', 'genome'],
      isGeneList: false,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable heatmap tab for gene lists', async () => {
    // mock exploreInfo from study
    const exploreInfo = {
      ...defaultExploreInfo,
      geneLists: ['Gene List 1', 'Gene List 2']
    }

    const exploreParams = {
      geneList: 'Gene List 1',
      userSpecified: {
        geneList: true
      },
      facets: ''
    }
    const expectedResults = {
      enabledTabs: ['geneListHeatmap'],
      disabledTabs: ['scatter', 'distribution', 'correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: true,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable scatter and distribution tabs when searching one gene', async () => {
    const exploreInfo = defaultExploreInfo

    const exploreParams = {
      cluster: 'foo',
      genes: ['Agpat2'],
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      userSpecified: {
        annotation: true,
        cluster: true,
        genes: true
      },
      facets: ''
    }

    const expectedResults = {
      enabledTabs: ['scatter', 'distribution'],
      disabledTabs: ['correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: false,
      isGene: true,
      isMultiGene: false,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable dotplot and heatmap tabs when searching multiple genes', async () => {
    const exploreInfo = {
      ...defaultExploreInfo
    }

    const exploreParams = {
      cluster: 'foo',
      genes: ['Agpat2', 'Apoe'],
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      userSpecified: {
        annotation: true,
        cluster: true,
        genes: true
      },
      facets: ''
    }

    const expectedResults = {
      enabledTabs: ['correlatedScatter', 'dotplot', 'heatmap'],
      disabledTabs: ['scatter', 'distribution'],
      isGeneList: false,
      isGene: true,
      isMultiGene: true,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable scatter, dotplot, and heatmap tabs when searching multiple genes', async () => {
    const exploreInfo = {
      ...defaultExploreInfo,
      spatialGroupNames: ['bing', 'baz'],
      spatialGroups: [
        { 'name': 'bing', 'associated_clusters': ['foo'] },
        { 'name': 'baz', 'associated_clusters': ['bar'] }
      ]
    }

    const exploreParams = {
      cluster: 'foo',
      genes: ['Agpat2', 'Apoe'],
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      spatialGroups: ['square', 'circle'],
      userSpecified: {
        annotation: true,
        cluster: true,
        genes: true,
        spatialGroups: true
      },
      facets: ''
    }

    const expectedResults = {
      enabledTabs: ['scatter', 'dotplot', 'heatmap'],
      disabledTabs: ['distribution', 'correlatedScatter'],
      isGeneList: false,
      isGene: true,
      isMultiGene: true,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable scatter, distribution, and dotplot tabs when searching multiple genes w/ consensus', async () => {
    const exploreInfo = defaultExploreInfo

    const exploreParams = {
      cluster: 'foo',
      genes: ['Agpat2', 'Apoe'],
      annotation: { name: 'bar', type: 'group', scope: 'study' },
      consensus: 'mean',
      userSpecified: {
        annotation: true,
        cluster: true,
        genes: true,
        consensus: true
      },
      facets: ''
    }

    const expectedResults = {
      enabledTabs: ['scatter', 'distribution', 'dotplot'],
      disabledTabs: [],
      isGeneList: false,
      isGene: true,
      isMultiGene: true,
      hasIdeogramOutputs: false
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('should enable infercnv-genome tab when selecting Ideogram annotations', async () => {
    const ideogramOpts = {
      '604fc5c4e241391a8ff93271': {
        'cluster': 'foo',
        'annotation': 'bar--group--study',
        'display': 'Observations: foo',
        'ideogram_settings': {
          'organism': 'human',
          'assembly': 'GRCh38',
          'annotationsPath': 'https://www.googleapis.com/storage/v1/b/my-bucket/o/ideogram_exp_means__Observations--foo--group--study.json?alt=media'
        }
      }
    }
    const exploreInfo = {
      ...defaultExploreInfo,
      clusterGroupNames: [],
      inferCNVIdeogramFiles: ideogramOpts
    }

    const exploreParams = {
      ideogramFileId: Object.keys(ideogramOpts)[0],
      userSpecified: {
        ideogramFileId: true
      },
      facets: ''
    }

    const expectedResults = {
      enabledTabs: ['infercnv-genome'],
      disabledTabs: ['scatter', 'distribution', 'correlatedScatter', 'dotplot', 'heatmap'],
      isGeneList: false,
      isGene: false,
      isMultiGene: false,
      hasIdeogramOutputs: true
    }

    expect(expectedResults).toEqual(getEnabledTabs(exploreInfo, exploreParams))
  })

  it('shows "Differential expression" button when clustering (but not current annotation) has DE results', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        differential_expression_frontend: true
      })

    const { container } = render((
      <ExploreDisplayTabs
        studyAccession={'SCP123'}
        exploreParams={exploreParamsDe}
        exploreParamsWithDefaults={exploreParamsDe}
        exploreInfo={exploreInfoDe}
      />
    ))

    const deButton = container.querySelector('.differential-expression-nondefault')
    expect(deButton).toHaveTextContent('Differential expression')
  })


  it('shows "Cell filtering" button when flag is enabled', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_cell_facet_filtering: true
      })

    render((
      <ExploreDisplayTabs
        studyAccession={'SCP123'}
        exploreParams={exploreParamsDe}
        exploreParamsWithDefaults={exploreParamsDe}
        exploreInfo={exploreInfoDe}
      />
    ))

    expect(screen.getByTestId('cell-filtering-button')).toHaveTextContent('Filter plotted cells')
  })

  it('disables cell filtering button', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_cell_facet_filtering: true
      })

    render(
      <ExploreDisplayPanelManager
        studyAccession={'SCP123'}
        exploreParams={exploreParamsDe}
        exploreParamsWithDefaults={exploreParamsDe}
        exploreInfo={exploreInfoDe}
        clusterCanFilter={false}
        filterErrorText={'Cluster is not indexed'}
        panelToShow={'options'}
      />
    )

    expect(screen.getByTestId('cell-filtering-button')).toHaveTextContent('Filtering unavailable')
  })

  it('Cell faceting handles new cluster that has annotations not in previous cluster', async () => {
    // Old set of selections, for previous clustering
    const cellFilteringSelection = {
      'cell_type__ontology_label--group--study': [
        'epithelial cell', 'macrophage', 'neutrophil', 'B cell',
        'T cell', 'dendritic cell', 'eosinophil', 'fibroblast'
      ],
      'infant_sick_YN--group--study': ['no', 'NA', 'yes']
    }


    // Raw material of selections for new clustering, which has an annotation not in previous clustering
    const newCellFaceting = {
      facets: [
        {
          'annotation': 'cell_type__ontology_label--group--study',
          'groups': ['epithelial cell'],
          'type': 'group',
          'isLoaded': true
        },
        {
          'annotation': 'infant_sick_YN--group--study',
          'groups': ['no', 'NA', 'yes'],
          'type': 'group',
          'isLoaded': true
        },
        {
          'annotation': 'Epithelial Cell Subclusters--group--cluster',
          'groups': [
            'Secretory Lactocytes', 'LC1', 'KRT high lactocytes 1', 'Cycling Lactocytes',
            'MT High Secretory Lactocytes', 'KRT high lactocytes 2'
          ],
          'type': 'group',
          'isLoaded': true
        }
      ]
    }

    // Mock function for React setter
    const setCellFilteringSelection = jest.fn()

    handleClusterSwitchForFiltering(cellFilteringSelection, newCellFaceting, setCellFilteringSelection)

    // Confirm React setter for selection includes new facet
    expect(setCellFilteringSelection).toHaveBeenCalledWith(
      expect.objectContaining({
        'Epithelial Cell Subclusters--group--cluster': [
          'Secretory Lactocytes', 'LC1', 'KRT high lactocytes 1', 'Cycling Lactocytes',
          'MT High Secretory Lactocytes', 'KRT high lactocytes 2'
        ]
      })
    )
  })
})
