import React from 'react'
import { render, fireEvent, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import OptionsButton, { configuredOptions } from '~/components/search/controls/OptionsButton'

describe('OptionsButton component', () => {
  it('renders the options button with correct icon and text', () => {
    const { getByText } = render(<OptionsButton />)

    expect(getByText('Options')).toBeInTheDocument()
  })

  it('toggles options visibility on click', () => {
    const { getByText, queryByText } = render(<OptionsButton />)

    // Initially, options should not be visible
    expect(queryByText('Include HCA results')).not.toBeInTheDocument()

    // Click to show options and confirm button i
    fireEvent.click(getByText('Options'))
    configuredOptions.map(option => {
      expect(getByText(option.label)).toBeInTheDocument()
    })
    expect(screen.getByTestId('search-options-button')).toHaveClass('active')

    // Click again to hide options
    fireEvent.click(getByText('Options'))
    expect(queryByText('Include HCA results')).not.toBeInTheDocument()
  })
})
