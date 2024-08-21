import { getPathwayGenes } from '~/lib/pathway-expression'

import { pathwayContainerHtml } from './pathway-expression.test-data.js'

describe('Expression overlay for pathway diagram', () => {
  it('colors pathway genes by expression', () => {
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
})
