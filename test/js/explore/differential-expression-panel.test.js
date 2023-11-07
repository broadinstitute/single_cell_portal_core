/* eslint-disable no-tabs */
/**
 * @fileoverview Tests for differential expression (DE) functionality
 */

import React from 'react'
import { render, fireEvent, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import DifferentialExpressionPanel from 'components/explore/DifferentialExpressionPanel'
import {
  PairwiseDifferentialExpressionGroupPicker, parseDeFile
} from 'components/visualization/controls/DifferentialExpressionGroupPicker'
import { exploreInfo, deObjects } from './differential-expression-panel.test-data'

describe('Differential expression panel', () => {
  it('renders DE genes table', async () => {
    // const deGroup = 'KRT high lactocytes 1'
    const deGroup = 'B cells'
    const deGenes = [
      {
        'size': 4.138,
        'significance': 1.547e-26,
        'name': 'CD74'
      },
      {
        'size': 3.753,
        'significance': 2.778e-24,
        'name': 'HLA-DPA1'
      },
      {
        'size': 3.753,
        'significance': 2.778e-24,
        'name': 'HLA-FOOBAR'
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

    const deHeaders = deObjects[0].select_options.headers

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
        deHeaders={deHeaders}
      />
    ))

    let deTable = container.querySelector('.de-table')
    expect(deTable).toHaveTextContent('HLA-DPA1')

    // Confirm sort
    const pvalAdjHeader = container.querySelector('#significance-header')
    const firstGeneBeforeSort = container.querySelector('.de-gene-row td')
    expect(firstGeneBeforeSort).toHaveTextContent('CD74')
    fireEvent.click(pvalAdjHeader)
    fireEvent.click(pvalAdjHeader)
    fireEvent.click(pvalAdjHeader)
    // screen.debug(deTable) // Print DE table HTML

    const firstGeneAfterSort = container.querySelector('.de-gene-row td')
    expect(firstGeneAfterSort).toHaveTextContent('HLA-DPA1')

    // Confirm base case for "Find genes"
    const deSearchBox = container.querySelector('.de-search-box')
    let input = deSearchBox.querySelector('input')
    fireEvent.change(input, { target: { value: 'CD7' } })
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(1)

    // Confirm behavior for clear icon ("x" at right in DE find search box)
    let clearIcon = container.querySelector('.clear-de-search-icon')
    fireEvent.click(clearIcon)
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(3)

    // Confirm multi-gene DE find
    fireEvent.change(input, { target: { value: 'HLA-' } })
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(2)

    // Clear gene names query
    clearIcon = container.querySelector('.clear-de-search-icon')
    fireEvent.click(clearIcon)
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(3)

    // Confirm "No genes found" message
    input = deSearchBox.querySelector('input')
    fireEvent.change(input, { target: { value: 'zxcv' } })
    const noGenesContainer = container.querySelector('.de-no-genes-found')
    expect(noGenesContainer).toHaveTextContent('No genes found.')
    clearIcon = container.querySelector('.clear-de-search-icon')
    fireEvent.click(clearIcon)

    // Confirm range slider facets appear, and can toggle
    const rangeSliderFacets = container.querySelectorAll('.de-slider-container')
    expect(rangeSliderFacets).toHaveLength(2)
    const log2FoldChangeCheckbox = container.querySelector('.slider-checkbox-significance')
    fireEvent.click(log2FoldChangeCheckbox)
    const inactiveFacets = container.querySelectorAll('.inactive.de-slider-container')
    expect(inactiveFacets).toHaveLength(1)

    // Confirm dot plot is invoked upon clicking related button
    deTable = container.querySelector('.de-table')
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(3)
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

describe('DE gene parsing', () => {
  it('correctly transforms SCP-computed DE file', () => {
    const tsvText =
      `names	scores	logfoldchanges	pvals	pvals_adj	pct_nz_group	pct_nz_reference
      0	CD74	11.55	4.138	7.695e-31	1.547e-26	1	0.7262
      1	HLA-DPA1	11.05	3.753	2.291e-28	2.778e-24	1	0.5595
      2	TCF4	10.92	7.512	9.554e-28	6.952e-24	0.8846	0.04085
      3	HLA-DPB1	10.79	3.461	3.818e-27	2.221e-23	1	0.6034`
    const deGenes = parseDeFile(tsvText)
    expect(deGenes[0].size).toEqual(4.138)
    expect(deGenes[0].significance).toEqual(1.547e-26)
  })

  it('correctly transforms ingest-processed author DE file', () => {
    const tsvText =
      `gene	avg_log2FC	p_val_adj	pct.2	pct.1	p_val
      0	ACE2	1.47710477	0.0	0.63504	0.8154	0.0
      1	CD274	1.171502945	0.0	0.5616	0.76314	0.0
      2	TP53	1.513586574	0.0	0.37492	0.68441	0.0`

    const isAuthorDe = true
    const deGenes = parseDeFile(tsvText, isAuthorDe)
    expect(deGenes[0].size).toEqual(1.477)
    expect(deGenes[0].significance).toEqual(0)
  })
})
