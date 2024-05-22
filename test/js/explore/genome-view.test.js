
import React from 'react'
import '@testing-library/jest-dom/extend-expect'
import { render, screen, waitFor } from '@testing-library/react'

import GenomeView from 'components/explore/GenomeView'

describe('IGV genome browser in Explore tab', () => {
  it('should show IGV tracks for BED and BAM files', async () => {
    const exploreInfo = null

    const studyAccession = 'SCP123'
    const trackFileName = ''
    const uniqueGenes = ['GAD1', 'LDLR', 'GAPDH', 'GCG', 'ACE2']
    const isVisible = true
    const exploreParams = { genes: 'GCG' }
    const updateExploreParams = () => {}

    const { container } = render((<GenomeView
      studyAccession={studyAccession}
      trackFileName={trackFileName}
      uniqueGenes={uniqueGenes}
      isVisible={isVisible}
      exploreParams={exploreParams}
      updateExploreParams={updateExploreParams}
    />))

    const igvRoot = container.querySelector('.igv-root-div')
    expect(igvRoot).toHaveLength(1)
  })
})
