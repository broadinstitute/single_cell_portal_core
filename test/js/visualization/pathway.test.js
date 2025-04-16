import React, { useState } from 'react'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import Plotly from 'plotly.js-dist'

import {getPathwayGenes, renderPathwayExpression} from 'lib/pathway-expression'
import {pathwaySvg, interestingNames} from './pathway.test-data'

describe('Pathway expression overlay diagrams', () => {
  beforeAll(() => {
    Element.prototype.insertAdjacentHTML = function (position, html) {
      const temp = document.createElement('div')
      temp.innerHTML = html
      while (temp.firstChild) {
        this.appendChild(temp.firstChild)
      }
    }
  })

  it('gets genes from pathway diagram', () => {

    // Mock pathway diagram for
    // "Mammary gland development: pregnancy and lactation - stage 3 of 4" (WP2817)
    document.body.innerHTML = `<div id="_ideogramPathwayContainer"></div>`;
    const container = document.getElementById('_ideogramPathwayContainer');
    container.insertAdjacentHTML('beforeend', pathwaySvg)

    // Mock Ideogram cache of gene names ranked by global interest
    window.Ideogram = {
      geneCache: {
        interestingNames
      }
    }

    const pathwayGenes = getPathwayGenes()

    expect(pathwayGenes).toHaveLength(70)
    expect(pathwayGenes[0]).toEqual({ domId: 'b7503', name: 'EGFR' })
  })

  // it('shows custom legend with default group scatter plot', () => {
  //   const studyAccession = 'SCP152'
  //   const cluster = 'All Cells UMAP'
  //   const annotation = { "name": "General_Celltype", "type": "group", "scope": "study", "values": [ "B cells", "CSN1S1 macrophages", "dendritic cells", "eosinophils", "fibroblasts", "GPMNB macrophages", "LC1", "LC2", "neutrophils", "removed", "T cells" ], "identifier": "General_Celltype--group--study", "color_map": { "B cells": "#e41a1c", "CSN1S1 macrophages": "#377eb8", "dendritic cells": "#4daf4a", "eosinophils": "#984ea3", "fibroblasts": "#ff7f00", "GPMNB macrophages": "#a65628", "LC1": "#f781bf", "LC2": "#999999", "neutrophils": "#66c2a5", "removed": "#fc8d62", "T cells": "#8da0cb" }}
  //   const label = 'B cells'
  //   const labels = ['B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1', 'LC2', 'neutrophils', 'T cells']

  // })
})
