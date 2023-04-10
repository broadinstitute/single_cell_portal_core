/**
 * @fileoverview Tests for differential expression (DE) functionality
 */

import React from 'react'
import { render, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import DifferentialExpressionPanel from 'components/explore/DifferentialExpressionPanel'
import {exploreInfo} from './differential-expression-panel.test-data'

describe('Differential expression panel', () => {
  it('renders DE genes table', async () => {
    const deGroup = 'KRT high lactocytes 1'
    const deGenes = [
      {
        'score': 77.55,
        'log2FoldChange': 3.434,
        'pval': 0,
        'pvalAdj': 0,
        'pctNzGroup': 0.9625,
        'pctNzReference': 0.5864,
        'name': 'SOD2'
      },
      {
        'score': 75.4,
        'log2FoldChange': 4.302,
        'pval': 0,
        'pvalAdj': 0,
        'pctNzGroup': 0.8543,
        'pctNzReference': 0.2124,
        'name': 'ANXA1'
      }
    ]

    const searchGenes = function() {}

    const exploreParamsWithDefaults = {
      'cluster': 'Epithelial Cells UMAP',
      'annotation': {
        'name': 'Epithelial Cell Subclusters',
        'type': 'group',
        'scope': 'cluster'
      },
      'genes': [
        'SOD2'
      ]
    }

    const clusterName = 'Epithelial Cells UMAP'
    const annotation = {
      'name': 'Epithelial Cell Subclusters',
      'type': 'group',
      'scope': 'cluster'
    }

    const setShowDeGroupPicker = function() {}
    const setDeGenes = function() {}
    const setDeGroup = function() {}

    const countsByLabel = {
      'Secretory Lactocytes': 25787,
      'LC1': 4920,
      'KRT high lactocytes 1': 3734,
      'Cycling Lactocytes': 604,
      'MT High Secretory Lactocytes': 3052,
      'KRT high lactocytes 2': 1728
    }

    const {container} = render((
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
    expect(deTable).toHaveTextContent('ANXA1')

    const deSearchBox = container.querySelector('.de-search-box')
    const input = deSearchBox.querySelector('input')
    fireEvent.change(input, { target: { value: 'SO' } })
    expect(deTable.querySelectorAll('.de-gene-row')).toHaveLength(1)
  })

})
