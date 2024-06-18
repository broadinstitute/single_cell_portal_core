
import React from 'react'
import '@testing-library/jest-dom/extend-expect'
import { render, screen, waitFor } from '@testing-library/react'
import SpatialSelector from 'components/visualization/controls/SpatialSelector'

const allSpatialGroups = [
  { name: 'spatial_letters', associated_clusters: ['X cluster'] },
  { name: 'spatial_square', associated_clusters: [] },
  { name: 'spatial_zigzag', associated_clusters: [] },
  { name: 'spatial_square_2', associated_clusters: [] },
  { name: 'spatial_square_3', associated_clusters: [] },
  { name: 'spatial_square_4', associated_clusters: [] },
  { name: 'spatial_square_5', associated_clusters: [] },
  { name: 'spatial_square_6', associated_clusters: [] },
  { name: 'spatial_square_7', associated_clusters: [] }
]

describe('Drop-down menu for spatial groups in Explore UI', () => {
  it('should show spatial selector', async () => {
    const spatialGroups = []
    const allSpatialGroups = [{ name: 'spatial_letters', associated_clusters: ['X cluster'] }]
    const genes = []

    const { container } = render((<SpatialSelector
      spatialGroups={spatialGroups}
      updateSpatialGroups={() => {}}
      allSpatialGroups={allSpatialGroups}
      genes={genes}
    />))


    const formLabel = container.querySelector('.labeled-select')
    expect(formLabel.textContent.includes('Spatial group')).toEqual(true)
  })

  it('should show plot-limit warning', async () => {
    const spatialGroups = [
      'spatial_letters', 'spatial_square', 'spatial_zigzag',
      'spatial_square_2', 'spatial_square_3', 'spatial_square_4',
      'spatial_square_5', 'spatial_square_6', 'spatial_square_7'
    ]
    const allSpatialGroups = []
    const genes = []

    const { container } = render((<SpatialSelector
      spatialGroups={spatialGroups}
      updateSpatialGroups={() => {}}
      allSpatialGroups={allSpatialGroups}
      genes={genes}
    />))

    const formLabel = container.querySelector('.warning-inline')
    expect(formLabel.textContent.includes('Remove groups to avoid plot limit')).toEqual(true)
  })
})
