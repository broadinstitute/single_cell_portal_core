import React from 'react'
import { render, screen, waitForElementToBeRemoved } from '@testing-library/react'
import '@testing-library/jest-dom'

import * as ScpApi from 'lib/scp-api'
import MyStudiesPage from 'components/my-studies/MyStudiesPage'


describe('My studies table', () => {
  it('renders a my studies table', async () => {
    const fakePlot = jest.spyOn(ScpApi, 'fetchEditableStudies')
    fakePlot.mockImplementation(() => Promise.resolve([{
      accession: 'SCP1',
      name: 'scp 1',
      id: { $oid: 'fakeId ' },
      authorEmail: 'scientist@science.edu',
      created_at: '2021-10-10',
      description: 'description of mock1 study'
    }]))
    render(<MyStudiesPage/>)
    await waitForElementToBeRemoved(() => screen.getByTestId('my-studies-spinner'))
    expect(screen.getByText('description of mock1 study')).toBeTruthy()
  })
})
