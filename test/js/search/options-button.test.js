import React from 'react'
import { render, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import OptionsButton from '~/components/search/controls/OptionsButton'

describe('OptionsButton component', () => {
  it('renders the options button with correct icon and text', () => {
    const { getByText } = render(<OptionsButton />)

    expect(getByText('Options')).toBeInTheDocument()
  })

  it('toggles options visibility on click', () => {
    const { getByText, queryByText } = render(<OptionsButton />)

    // Initially, options should not be visible
    expect(queryByText('Include HCA results')).not.toBeInTheDocument()

    // Click to show options
    fireEvent.click(getByText('Options'))
    expect(getByText('Include HCA results')).toBeInTheDocument()

    // Click again to hide options
    fireEvent.click(getByText('Options'))
    expect(queryByText('Include HCA results')).not.toBeInTheDocument()
  })
})
