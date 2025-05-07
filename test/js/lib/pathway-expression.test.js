import {
  getPathwayGenes, colorPathwayGenesByExpression,
  getDotPlotGeneBatches
} from '~/lib/pathway-expression'
import * as UserProvider from '~/providers/UserProvider'

import {
  pathwayContainerHtml, dotPlotMetrics, manyPathwayGenes
} from './pathway-expression.test-data.js'

import { interestingNames } from './../visualization/pathway.test-data'

describe('Expression overlay for pathway diagram', () => {
  beforeAll(() => {
    // Mock Ideogram cache of gene names ranked by global interest
    window.Ideogram = {
      geneCache: {
        interestingNames
      }
    }
  })

  it('gets objects containing e.g. DOM ID for genes in pathway ', () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    const body = document.querySelector('body')
    body.insertAdjacentHTML('beforeend', pathwayContainerHtml)
    // Helpful debug technique:
    // const containerDom = document.querySelector('#_ideogramPathwayContainer')
    // console.log('containerDom', containerDom)
    const ranks = ['CSN2', 'NR3C1', 'EGFR', 'PRL']
    const pathwayGenes = getPathwayGenes().filter(g => ranks.includes(g.name))
    expect(pathwayGenes).toHaveLength(4)
    expect(pathwayGenes[0]).toEqual({ domId: 'c2df9', name: 'EGFR' })
  })

  it('colors pathway genes by expression', () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    const body = document.querySelector('body')
    body.insertAdjacentHTML('beforeend', pathwayContainerHtml)
    const ranks = ['CSN2', 'NR3C1', 'EGFR', 'PRL']
    const pathwayGenes = getPathwayGenes().filter(g => ranks.includes(g.name))

    const annotationLabel = 'LC2'

    colorPathwayGenesByExpression(annotationLabel, dotPlotMetrics)

    const egfrDomId = pathwayGenes.find(g => g.name === 'EGFR').domId
    const egfrRectNode = document.querySelector(`#${egfrDomId} rect`)

    const egfrStyle = getComputedStyle(egfrRectNode)
    const egfrColor = egfrStyle.fill

    // Blue-ish purple (#6800a1) -- base color for scaled mean expression
    // Roughly 88% white / 12% purple -- for percent of cells expressing
    // See color-mix() on MDN:
    // https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix
    expect(egfrColor).toBe('color-mix(in oklab, #6800a1 12.350979804992676%, white)')
  })

  it('splits big lists of dot plot genes in batches of 50 or less', () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    expect(manyPathwayGenes).toHaveLength(275)
    const dotPlotGeneBatches = getDotPlotGeneBatches(manyPathwayGenes)

    expect(dotPlotGeneBatches).toHaveLength(6)
    expect(dotPlotGeneBatches[0]).toHaveLength(50)

    // N.B.: Not 25, because there are 18 duplicate gene names in manyPathwayGenes.
    // That's because manyPathwayGenes represents _graphical_ nodes in the diagram,
    // whereas entries in dotPlotGeneBatches represent _genes we want metrics for_,
    // and those are unique by gene name.
    expect(dotPlotGeneBatches.slice(-1)[0]).toHaveLength(7)
  })

})
