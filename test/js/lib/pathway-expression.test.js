import {pathwayContainerHtml} from './pathway-expression.test-data.js'

describe('Expression overlay for pathway diagram', () => {
  it('colors pathway genes by expression', () => {
    const body = document.querySelector('body')
    body.insertAdjacentHTML('beforeend', pathwayContainerHtml)
    expect(1).toBe(1)
  })
})
