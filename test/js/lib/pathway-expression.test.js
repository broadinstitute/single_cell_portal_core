import { getPathwayGenes, colorPathwayGenesByExpression } from '~/lib/pathway-expression'
import * as UserProvider from '~/providers/UserProvider'

import { pathwayContainerHtml, dotPlotMetrics } from './pathway-expression.test-data.js'

describe('Expression overlay for pathway diagram', () => {
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
    const pathwayGenes = getPathwayGenes(ranks)
    expect(pathwayGenes).toHaveLength(4)
    expect(pathwayGenes[0]).toEqual({ domId: 'e8c90', name: 'CSN2' })
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
    const pathwayGenes = getPathwayGenes(ranks)
    const annotationLabel = 'LC2'

    colorPathwayGenesByExpression(pathwayGenes, dotPlotMetrics, annotationLabel)

    const egfrDomId = pathwayGenes.find(g => g.name === 'EGFR').domId
    const egfrRectNode = document.querySelector(`#${egfrDomId} rect`)
    const egfrStyle = getComputedStyle(egfrRectNode)
    const egfrColor = egfrStyle.fill

    // Blue-ish purple (#6800a1) -- base color for scaled mean expression
    // Roughly 88% white / 12% purple -- for percent of cells expressing
    // See color-mix() on MDN:
    // https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix
    expect(egfrColor).toBe('color-mix(in oklab, #6800a1 12.350979804992676%, white)')

    expect(1).toBe(1)
  })
})
