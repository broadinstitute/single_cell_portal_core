/** Emulates D3 scaleLinear, but avoids D3's ES6 import compilation issues */
export function scaleLinear(domain, range) {
  const intervals = []

  for (let i = 0; i < domain.length - 1; i++) {
    const [domainMin, domainMax] = [domain[i], domain[i + 1]]
    const [rangeMin, rangeMax] = [range[i], range[i + 1]]

    const domainLength = domainMax - domainMin
    const rangeLength = rangeMax - rangeMin

    intervals.push({
      domain: [domainMin, domainMax],
      range: [rangeMin, rangeMax],
      domainLength,
      rangeLength
    })
  }

  /** Provides a multi-interval linear scale */
  function scale(x) {
    for (const interval of intervals) {
      const { domain, range, domainLength, rangeLength } = interval
      if (x >= domain[0] && x <= domain[1]) {
        return range[0] + ((x - domain[0]) / domainLength) * rangeLength
      }
    }
  }

  scale.invert = function(y) {
    for (const interval of intervals) {
      const { domain, range, domainLength, rangeLength } = interval
      if (y >= range[0] && y <= range[1]) {
        return domain[0] + ((y - range[0]) / rangeLength) * domainLength
      }
    }
  }

  return scale
}
