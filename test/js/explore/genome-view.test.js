
import React from 'react'
const fetch = require('node-fetch')
import '@testing-library/jest-dom/extend-expect'
import { render, screen, waitFor } from '@testing-library/react'
import igv from '@single-cell-portal/igv'
import * as IgvUtils from 'lib/igv-utils'
import GenomeView, { getIgvOptions, filterIgvFeatures } from 'components/explore/GenomeView'
import { trackInfo } from './genome-view.test.data.js'

describe('IGV genome browser in Explore tab', () => {
  beforeAll(() => {
    global.fetch = fetch
  })

  it('should show spinner while IGV does not have content', async () => {
    const studyAccession = 'SCP123'
    const trackFileName = ''
    const uniqueGenes = ['GAD1', 'LDLR', 'GAPDH', 'GCG', 'ACE2']
    const isVisible = true
    const queriedGenes = ['GCG']
    const updateExploreParams = () => {}

    const { container } = render((<GenomeView
      studyAccession={studyAccession}
      trackFileName={trackFileName}
      uniqueGenes={uniqueGenes}
      isVisible={isVisible}
      queriedGenes={queriedGenes}
      updateExploreParams={updateExploreParams}
    />))


    const spinner = container.querySelector('.gene-load-spinner')
    expect(spinner.getAttribute('data-icon')).toEqual('dna')
  })

  it('should get IGV configuration object', async () => {
    const tracks = trackInfo.tracks
    const gtfFiles = trackInfo.gtfFiles
    const uniqueGenes = ['GAD1', 'LDLR', 'GAPDH', 'GCG', 'ACE2']
    const queriedGenes = ['GCG']

    const igvOptions = getIgvOptions(tracks, gtfFiles, uniqueGenes, queriedGenes)

    expect(igvOptions.reference).toEqual('hg38')
  })

  it('should filter genomic features in IGV', async () => {
    // Mock function that wraps a set of IGV calls
    const updateTrack = jest.spyOn(IgvUtils, 'updateTrack')
    updateTrack.mockImplementation(() => {})

    const filteredCellNames = new Set(['GAT-1', 'TAC-1', 'AGA-1'])
    const features = [
      { name: 'GAT-1', score: 1, start: 125, end: 130 },
      { name: 'TAC-1', score: 1, start: 125, end: 130 },
      { name: 'AGA-1', score: 2, start: 97, end: 102 },
      { name: 'AAA-1', score: 2, start: 125, end: 130 },
      { name: 'TTT-1', score: 3, start: 125, end: 130 },
      { name: 'CCC-1', score: 4, start: 125, end: 130 },
      { name: 'GGG-1', score: 5, start: 125, end: 130 }
    ]

    const filteredFeatures = [
      { name: 'GAT-1', score: 1, start: 125, end: 130 },
      { name: 'TAC-1', score: 1, start: 125, end: 130 },
      { name: 'AGA-1', score: 2, start: 97, end: 102 }
    ]

    const igvBrowser = {
      referenceFrameList: [{ start: 100, end: 200 }],
      tracks: [{ trackView: { viewports: [{ featureCache: { chr: 'chr9' } }] } }],
      trackViews: [
        {}, {}, {}, {}, {
          track: {
            featureSource: {
              featureCache: {
                allFeatures: {
                  chr9: features
                }
              }
            }
          }
        }
      ]
    }

    global.igvBrowser = igvBrowser

    filterIgvFeatures(filteredCellNames)

    const trackIndex = 4
    expect(updateTrack).toHaveBeenLastCalledWith(
      trackIndex, filteredFeatures, igv, igvBrowser
    )
  })
})
