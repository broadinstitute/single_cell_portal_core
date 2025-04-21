import React, { useState } from 'react'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import Plotly from 'plotly.js-dist'
import jquery from 'jquery'
import { mockPerformance } from '../mock-performance'

import Pathway from 'components/visualization/Pathway'
import * as PathwayExpression from 'lib/pathway-expression'
import {
  pathwaySvg, interestingNames, pathwayGenes, countsByLabel, morpheusJson,
  dotPlotMetrics
} from './pathway.test-data'
import * as ScpApi from 'lib/scp-api'

const getPathwayGenes = PathwayExpression.getPathwayGenes
const renderPathwayExpression = PathwayExpression.renderPathwayExpression
const colorPathwayGenesByExpression = PathwayExpression.colorPathwayGenesByExpression

describe('Pathway expression overlay library', () => {
  beforeAll(() => {
    Element.prototype.insertAdjacentHTML = function(position, html) {
      const temp = document.createElement('div')
      temp.innerHTML = html
      while (temp.firstChild) {
        this.appendChild(temp.firstChild)
      }
    }

    // Mock pathway diagram for
    // "Mammary gland development: pregnancy and lactation - stage 3 of 4" (WP2817)
    document.body.innerHTML =
      `<div id="_ideogramPathwayContainer">` +
        `<div class="_ideoPathwayHeader">` +
          `<a href="https://wikipathways.org/pathways/WP2817" target="_blank">` +
            `Mammary gland development: pregnancy and lactation - stage 3 of 4` +
            `</a>` +
        `</div>` +
      `</div>`;
    const container = document.getElementById('_ideogramPathwayContainer');
    container.insertAdjacentHTML('beforeend', pathwaySvg)

    // Mock Ideogram cache of gene names ranked by global interest
    window.Ideogram = {
      geneCache: {
        interestingNames
      },
      drawPathway() {
        document.dispatchEvent(new Event('ideogramDrawPathway'))
      }
    }

    window.SCP = {}
    window.SCP.countsByLabel = countsByLabel

    window.SCP.renderBackgroundDotPlotRegister = {}
    mockPerformance('')

    global.$ = jquery
  })

  it('renders React component', () => {

    const studyAccession = 'SCP152'
    const cluster = 'All Cells UMAP'
    const annotation = { 'name': 'General_Celltype', 'type': 'group', 'scope': 'study', 'values': [ 'B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1', 'LC2', 'neutrophils', 'removed', 'T cells' ], 'identifier': 'General_Celltype--group--study', 'color_map': { 'B cells': '#e41a1c', 'CSN1S1 macrophages': '#377eb8', 'dendritic cells': '#4daf4a', 'eosinophils': '#984ea3', 'fibroblasts': '#ff7f00', 'GPMNB macrophages': '#a65628', 'LC1': '#f781bf', 'LC2': '#999999', 'neutrophils': '#66c2a5', 'removed': '#fc8d62', 'T cells': '#8da0cb' }}
    const label = 'B cells'
    const pathway = 'WP2817'
    const dimensions = { width: 800, height: 600 }
    const labels = ['B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1', 'LC2', 'neutrophils', 'T cells']
    const queryFn = function() {}

    render(
      <Pathway
        studyAccession={studyAccession}
        cluster={cluster}
        annotation={annotation}
        label={label}
        pathway={pathway}
        dimensions={dimensions}
        labels={labels}
        queryFn={queryFn}
      />
    )

    const buttons = document.querySelectorAll('.terra-secondary-btn')
    expect(buttons[0].innerHTML).toContain('Genes')

  })

  it('gets genes from pathway diagram', () => {
    const pathwayGenes = getPathwayGenes()

    expect(pathwayGenes).toHaveLength(70)
    expect(pathwayGenes[0]).toEqual({ domId: 'b7503', name: 'EGFR' })
  })

  it('makes API call to render pathway expression', async () => {
    const getPathwayGenesSpy = jest.spyOn(PathwayExpression, 'getPathwayGenes')
    getPathwayGenesSpy.mockImplementation(() => pathwayGenes)

    const fetchMorpheusJson = jest.spyOn(ScpApi, 'fetchMorpheusJson')
    fetchMorpheusJson.mockImplementation(() => Promise.resolve(morpheusJson))

    window.morpheus = {
      BufferedReader: {},
      Util: {},
      HeatMap: function Heatmap() {}
    }

    const studyAccession = 'SCP152'
    const cluster = 'All Cells UMAP'
    const annotation = { 'name': 'General_Celltype', 'type': 'group', 'scope': 'study', 'values': [ 'B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1', 'LC2', 'neutrophils', 'removed', 'T cells' ], 'identifier': 'General_Celltype--group--study', 'color_map': { 'B cells': '#e41a1c', 'CSN1S1 macrophages': '#377eb8', 'dendritic cells': '#4daf4a', 'eosinophils': '#984ea3', 'fibroblasts': '#ff7f00', 'GPMNB macrophages': '#a65628', 'LC1': '#f781bf', 'LC2': '#999999', 'neutrophils': '#66c2a5', 'removed': '#fc8d62', 'T cells': '#8da0cb' }}
    const label = 'B cells'
    const labels = ['B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1', 'LC2', 'neutrophils', 'T cells']

    await renderPathwayExpression(studyAccession, cluster, annotation, label, labels)

    expect(fetchMorpheusJson).toHaveBeenCalled()
  })

  it('adds metrics for pathway nodes based on expression', async () => {
    colorPathwayGenesByExpression('B cells', dotPlotMetrics)

    const yy1GeneNode = document.querySelector('#a8005 rect')

    const scaledMeanExpression = parseFloat(yy1GeneNode.getAttribute('data-scaled-mean-expression'))
    const percentExpressing = parseInt(yy1GeneNode.getAttribute('data-percent-expressing'))

    expect(scaledMeanExpression).toBeGreaterThan(1.25)
    expect(scaledMeanExpression).toBeLessThan(1.26)
    expect(percentExpressing).toEqual(75)
  })
})
