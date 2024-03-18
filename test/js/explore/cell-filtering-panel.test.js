import React from 'react'
import { render, fireEvent, screen, waitFor } from '@testing-library/react'

import * as UserProvider from '~/providers/UserProvider'
import { CellFilteringPanel } from '~/components/explore/CellFilteringPanel'
import {
  annotationList, cellFaceting, cellFilteringSelection, cellFilterCounts
} from './cell-filtering-panel.test-data'
import '@testing-library/jest-dom/extend-expect'

cellFaceting.filterCounts = cellFilterCounts

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

  it('sorts filters alphabetically on sort-icon click', async () => {
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

    const firstFilter = container.querySelector('.cell-filter-label')
    expect(firstFilter).toHaveTextContent('epithelial cell')
    expect(firstFilter).toHaveTextContent('39825')

    const sortFiltersIcon = container.querySelector('.sort-filters')
    fireEvent.click(sortFiltersIcon)

    const firstFilterAfterSort = container.querySelector('.cell-filter-label')

    expect(firstFilterAfterSort).toHaveTextContent('B cell')
    expect(firstFilterAfterSort).toHaveTextContent('52')
  })

  it('renders numeric cell facet, which is interactive', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_numeric_cell_filtering: true
      })

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

    const lastFacet = Array.from(container.querySelectorAll('.cell-facet')).slice(-1)[0]
    const lastFacetName = lastFacet.querySelector('.cell-facet-name')
    expect(lastFacetName).toHaveTextContent('BMI pre pregnancy')

    const sliderId = 'numeric-filter-histogram-slider___BMI_pre_pregnancy--numeric--study'
    const histogram = container.querySelector(`#${ sliderId}`)

    // Confirm left and right handles for slider
    const handlebars = histogram.querySelectorAll('.handlebar')
    expect(handlebars).toHaveLength(2)

    // Confirm slider, and that its layout accounts for special "N/A" bar
    const sliderSelection = histogram.querySelector('.selection')
    const sliderOffset = sliderSelection.getAttribute('x')
    const sliderWidth = sliderSelection.getAttribute('width')

    // Confirm minimum value of 18.8356789 in test data gets rounded to 2
    // decimal places; without which this offset becomes "24.044423180157942" (SCP-5555)
    const expectedOffset = '24'
    expect(sliderOffset).toEqual(expectedOffset)
    expect(sliderWidth).toEqual('155')

    // Confirm clicking "N/A" checkbox calls filtering code
    const naCheckbox = lastFacet.querySelector('.numeric-na-filter')
    fireEvent.click(naCheckbox)
    expect(updateFilteredCells).toHaveBeenCalledWith(
      expect.objectContaining({
        'BMI_pre_pregnancy--numeric--study': [
          [['between', [18.84, 34.01]]], false
        ]
      })
    )
  })
})
