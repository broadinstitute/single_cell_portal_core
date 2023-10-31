import React from 'react'
import { render, fireEvent, screen, waitFor } from '@testing-library/react'
import { CellFilteringPanel } from '~/components/explore/CellFilteringPanel'
import {
  annotationList, cellFaceting, cellFilteringSelection, cellFilterCounts
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
        cellFilteringSelection={cellFilteringSelection}
        cellFilterCounts={cellFilterCounts}
        updateFilteredCells={updateFilteredCells}
      />
    )

    // screen.debug(container) // Print cell filtering panel HTML

    const header = container.querySelector('.filter-section-header')

    expect(header).toHaveTextContent('Filter by')
  })

  it('toggles facet collapse on chevron click', async () => {
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
        cellFilteringSelection={cellFilteringSelection}
        cellFilterCounts={cellFilterCounts}
        updateFilteredCells={updateFilteredCells}
      />
    )

    // screen.debug(container) // Print cell filtering panel HTML

    const allFacetsToggle = container.querySelector('.filter-section-header .facet-toggle-chevron')

    fireEvent.click(allFacetsToggle)

    const facetHeaders = document.querySelectorAll('.cell-facet-header')
    const isAllFacetsHidden = Array.from(facetHeaders).every(
      facetNode => Array.from(facetNode.classList).includes('cell-filters-hidden')
    )
    expect(isAllFacetsHidden).toEqual(true)
  })

  it('deselects all filters in facet on parent checkbox click', async () => {
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
        cellFilteringSelection={cellFilteringSelection}
        cellFilterCounts={cellFilterCounts}
        updateFilteredCells={updateFilteredCells}
      />
    )

    // screen.debug(container, 300000) // Print cell filtering panel HTML
    const facetCheckbox = container.querySelector('.cell-facet-header-checkbox')
    fireEvent.click(facetCheckbox)

    expect(updateFilteredCells).toHaveBeenCalledWith(
      expect.objectContaining({
        'cell_type__ontology_label--group--study': []
      })
    )
  })
})
