/**
 * @fileoverview Tests for differential expression (DE) functionality
 */

import React from 'react'
import { render, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import DifferentialExpressionPanel from 'components/explore/DifferentialExpressionPanel'
import {
  PairwiseDifferentialExpressionGroupPicker
} from 'components/visualization/controls/DifferentialExpressionGroupPicker'
import { exploreInfo, deObjects } from './differential-expression-panel.test-data'

describe('Differential expression panel', () => {
  it('renders DE genes table', async () => {
    // const deGroup = 'KRT high lactocytes 1'
    const deGroup = 'B cells'
    const deGenes = [
      {
        'score': 11.55,
        'log2FoldChange': 4.138,
        'pval': 7.695e-31,
        'pvalAdj': 1.547e-26,
        'pctNzGroup': 1,
        'pctNzReference': 0.7262,
        'name': 'CD74'
      },
      {
        'score': 11.05,
        'log2FoldChange': 3.753,
        'pval': 2.291e-28,
        'pvalAdj': 2.778e-24,
        'pctNzGroup': 1,
        'pctNzReference': 0.5595,
        'name': 'HLA-DPA1'
      }
    ]

    const searchGenes = jest.fn()

    const exploreParamsWithDefaults = {
      'cluster': 'All Cells UMAP',
      'annotation': {
        'name': 'General_Celltype',
        'type': 'group',
        'scope': 'study'
      },
      'genes': [
        'CD74'
      ]
    }

    const clusterName = 'All Cells UMAP'
    const annotation = {
      'name': 'General_Celltype',
      'type': 'group',
      'scope': 'study'
    }

    const setShowDeGroupPicker = function() {}
    const setDeGenes = function() {}
    const setDeGroup = function() {}

    const countsByLabel = {
      'LC2': 35398,
      'GPMNB macrophages': 5318,
      'LC1': 4427,
      'neutrophils': 835,
      'B cells': 52,
      'T cells': 792,
      'dendritic cells': 425,
      'CSN1S1 macrophages': 1066,
      'eosinophils': 25,
      'fibroblasts': 140
    }

    const { container } = render((
      <DifferentialExpressionPanel
        deGroup={deGroup}
        deGenes={deGenes}
        searchGenes={searchGenes}
        exploreParamsWithDefaults={exploreParamsWithDefaults}
        exploreInfo={exploreInfo}
        clusterName={clusterName}
        bucketId={exploreInfo?.bucketId}
        annotation={annotation}
        setShowDeGroupPicker={setShowDeGroupPicker}
        setDeGenes={setDeGenes}
        setDeGroup={setDeGroup}
        countsByLabel={countsByLabel}
      />
    ))

    const deTable = container.querySelector('.de-table')
    expect(deTable).toHaveTextContent('HLA-DPA1')

    // Confirm sort
    const pvalAdjHeader = container.querySelector('#pval-adj-header')
    const firstGeneBeforeSort = container.querySelector('.de-gene-row td')
    expect(firstGeneBeforeSort).toHaveTextContent('CD74')
    fireEvent.click(pvalAdjHeader)
    fireEvent.click(pvalAdjHeader)
    fireEvent.click(pvalAdjHeader)
    // screen.debug(deTable) // Print DE table HTML

    const firstGeneAfterSort = container.querySelector('.de-gene-row td')
    expect(firstGeneAfterSort).toHaveTextContent('HLA-DPA1')

    // Confirm "Find a gene"
    const deSearchBox = container.querySelector('.de-search-box')
    const input = deSearchBox.querySelector('input')
    fireEvent.change(input, { target: { value: 'CD7' } })
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(1)

    // Confirm dot plot is invoked upon clicking related button
    const deDotPlotButton = container.querySelector('.de-dot-plot-button')
    fireEvent.click(deDotPlotButton)
    expect(searchGenes).toHaveBeenCalled()
  })

  it('renders pairwise group picker', async () => {
    // const deGroup = 'KRT high lactocytes 1'
    const deGroup = null
    const deGroupB = null
    const deGenes = null
    const hasOneVsRestDe = true

    const searchGenes = jest.fn()

    const clusterName = 'All Cells UMAP'
    const annotation = {
      'name': 'General_Celltype',
      'type': 'group',
      'scope': 'study'
    }

    const setShowDeGroupPicker = function() {}
    const setDeGenes = function() {}
    const setDeGroup = function() {}
    const setDeFilePath = function() {}
    const setDeGroupB = function() {}

    const countsByLabel = {
      'LC2': 35398,
      'GPMNB macrophages': 5318,
      'LC1': 4427,
      'neutrophils': 835,
      'B cells': 52,
      'T cells': 792,
      'dendritic cells': 425,
      'CSN1S1 macrophages': 1066,
      'eosinophils': 25,
      'fibroblasts': 140
    }


    const bucketId = 'fc-febd4c65-881d-497f-b101-01a7ec427e6a'

    const { container } = render((
      <PairwiseDifferentialExpressionGroupPicker
        bucketId={bucketId}
        clusterName={clusterName}
        annotation={annotation}
        setShowDeGroupPicker={setShowDeGroupPicker}
        deGenes={deGenes}
        setDeGenes={setDeGenes}
        deGroup={deGroup}
        setDeGroup={setDeGroup}
        countsByLabel={countsByLabel}
        deObjects={deObjects}
        setDeFilePath={setDeFilePath}
        deGroupB={deGroupB}
        setDeGroupB={setDeGroupB}
        hasOneVsRestDe={hasOneVsRestDe}
      />
    ))

    // Ensure options in menu A display by default
    const pairwiseSelectA = container.querySelector('.pairwise-select')
    expect(pairwiseSelectA).toHaveTextContent('CSN1S1 macrophages')
  })
})
