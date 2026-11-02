import React from 'react'
import { render, waitForElementToBeRemoved, screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom'

import * as ScpApi from 'lib/scp-api'
import Plotly from 'plotly.js-dist'
import StudyUsageInfo from 'components/my-studies/StudyUsageInfo'


describe('Usage info for a given study', () => {
  it('renders data from the api call', async () => {
    const fetchUsageInfo = jest.spyOn(ScpApi, 'fetchStudyUsage')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchUsageInfo.mockImplementation(() => Promise.resolve(
      {
        bulkDownloads: {
          data: {
            series: ['2022-01-01', '2022-02-01', '2022-03-01'],
            values: { '2022-01-01': 0, '2022-02-01': 2, '2022-03-01': 1 }
          }
        },
        fileDownloads: {
          data: {
            series: ['2022-01-01', '2022-02-01', '2022-03-01'],
            values: { '2022-01-01': 3, '2022-02-01': 4, '2022-03-01': 0 }
          }
        },
        pageViews: {
          data: {
            series: ['2022-01-01', '2022-02-01', '2022-03-01'],
            values: { '2022-01-01': 13, '2022-02-01': 15, '2022-03-01': 19 }
          }
        }
      }
    ))
    const mockPlotlyReact = jest.spyOn(Plotly, 'react')
    mockPlotlyReact.mockImplementation(() => {})
    const study = {
      accession: 'SCP12',
      name: 'Test study 12',
      _id: { $oid: 'fakeId4' }
    }
    render(<StudyUsageInfo study={study}/>)
    await waitForElementToBeRemoved(() => screen.getByTestId('study-usage-spinner'))
    expect(fetchUsageInfo).toHaveBeenLastCalledWith('SCP12')

    expect(mockPlotlyReact).toHaveBeenLastCalledWith('study-usage-graph-2', [{
      type: 'bar',
      x: ['2022-01-01', '2022-02-01', '2022-03-01'],
      y: [3, 6, 1]
    }], {
      xaxis: { title: 'Month' },
      yaxis: { title: 'Download events' }
    })
  })
})
