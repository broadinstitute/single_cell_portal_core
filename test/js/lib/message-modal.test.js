import React from 'react'
import { render, screen, act, fireEvent, waitForElementToBeRemoved } from '@testing-library/react'
import '@testing-library/jest-dom'

import MessageModal, { showMessage } from 'lib/MessageModal'

describe('Message modal renders when called', () => {
  it('shows message when showMessage is called', async () => {
    render((
      <div>
        <MessageModal/>
        other content here
      </div>
    ))
    expect(screen.queryAllByRole('dialog')).toEqual([])
    expect(screen.queryAllByRole('button')).toEqual([])

    act(() => {
      showMessage('message of importance', 'foo-key')
    })
    await screen.findByText('message of importance')
    expect(screen.getByRole('button')).toHaveTextContent('OK')

    fireEvent.click(screen.getByRole('button'))
    expect(screen.queryAllByRole('dialog')).toEqual([])
    expect(screen.queryAllByRole('button')).toEqual([])
  })
})
