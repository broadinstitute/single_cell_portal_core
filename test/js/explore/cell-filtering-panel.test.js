import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import { CellFilteringPanel } from '~/components/explore/CellFilteringPanel'
import {
  annotationList,
  cellFaceting
} from './cell-filtering-panel.test-data'
import '@testing-library/jest-dom/extend-expect'

describe('"Cell filtering" panel', () => {
  it('renders initially', async () => {
    const cluster = 'All Cells UMAP'
    const shownAnnotation = {
      'name': 'General_Celltype',
      'type': 'group',
      'scope': 'study',
      'isDisabled': false
    }

    // Mock functions
    const updateClusterParams = jest.fn()
    const updateFilteredCells = jest.fn()

    const { container } = render(
      <CellFilteringPanel
        annotationList={annotationList}
        cluster={cluster}
        shownAnnotation={shownAnnotation}
        updateClusterParams={updateClusterParams}
        cellFaceting={cellFaceting}
        updateFilteredCells={updateFilteredCells}
      />
    )

    // screen.debug(container) // Print cell filtering panel HTML

    const header = container.querySelector('h5')

    expect(header).toHaveTextContent('Filter by')
  })
})
