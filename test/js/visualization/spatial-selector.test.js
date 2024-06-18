
import React from 'react'
import '@testing-library/jest-dom/extend-expect'
import { render, screen, waitFor } from '@testing-library/react'
import SpatialSelector from 'components/visualization/controls/SpatialSelector'

describe('Drop-down menu for spatial groups in Explore UI', () => {
  it('should show spatial selector', async () => {
    const allSpatialGroups = []
    const spatialGroups = []
    const genes = []

    const { container } = render((<SpatialSelector
      allSpatialGroups={allSpatialGroups}
      spatialGroups={spatialGroups}
      updateSpatialGroups={() => {}}
      genes={genes}
    />))


    const formLabel = container.querySelector('.labeled-select')
    expect(formLabel.textContent.includes('Spatial group')).toEqual(true)
  })
})
