import React from 'react'
import { render, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import OptionsControl from '~/components/search/controls/OptionsControl'

describe('OptionsControl component', () => {
  it('renders with default checked state', () => {
    const searchContext = {
      params: { 'external': 'hca' },
      updateSearch: jest.fn()
    }
    const { getByText, getByRole } = render(
      <OptionsControl searchContext={searchContext} searchProp='external' value='hca' label='Include HCA results' />
    )

    expect(getByText('Include HCA results')).toBeInTheDocument()
    expect(getByRole('checkbox')).toBeChecked()
  })

  it('toggles checkbox state on click', () => {
    const searchContext = {
      params: { 'external': 'hca' },
      updateSearch: jest.fn()
    }
    const { getByRole, getByText } = render(
      <OptionsControl searchContext={searchContext} searchProp='external' value='hca' label='Include HCA results' />
    )

    const checkbox = getByRole('checkbox')
    fireEvent.click(checkbox)

    expect(checkbox).not.toBeChecked()
    expect(searchContext.updateSearch).toHaveBeenCalledWith({ 'external': null })

    fireEvent.click(getByText('Include HCA results'))

    expect(checkbox).toBeChecked()
    expect(searchContext.updateSearch).toHaveBeenCalledWith({ 'external': 'hca' })
  })
})
