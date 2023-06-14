import React from 'react'
import { render, waitForElementToBeRemoved, screen, fireEvent } from '@testing-library/react'
import camelcaseKeys from 'camelcase-keys'
import '@testing-library/jest-dom/extend-expect'
import { setMockOrigin } from 'lib/scp-api'

import DownloadSelectionModal from 'components/search/controls/download/DownloadSelectionModal'
import * as ScpApi from 'lib/scp-api'

const EXAMPLE_HUMAN_SYNTH_STUDY_DOWNLOAD_INFO = [
  {
    'name': 'Human Male Islet cells and Cataracts',
    'accession': 'SCP12',
    'description': 'bleh',
    'study_source': 'SCP',
    'study_files': [
      {
        'name': 'metadata.tsv',
        'id': '60403d30cc7ba03f94477640',
        'file_type': 'Metadata',
        'upload_file_size': 24694
      }
    ]
  },
  {
    'name': 'Human Blood Study with no metadata',
    'accession': 'SCP31',
    'description': 'bleh',
    'study_source': 'SCP',
    'study_files': []
  },
  {
    'name': 'Human raw counts',
    'accession': 'SCP35',
    'study_source': 'SCP',
    'description': 'bleh',
    'study_files': [
      {
        'name': 'raw1_human_5k_cells_80_genes.metadata.txt',
        'id': '60a2cf62cc7ba082358b545f',
        'file_type': 'Metadata',
        'upload_file_size': 215081
      },
      {
        'name': 'DELETE-9ffbd0d1-f385-4cc0-8c58-1d22d253b8de',
        'id': '60a2cf63cc7ba082358b5461',
        'file_type': 'DELETE',
        'upload_file_size': 1005150
      },
      {
        'name': 'raw1_human_5k_cells_80_genes.cluster_2D.txt',
        'id': '60a2cf63cc7ba082358b5464',
        'file_type': 'Cluster',
        'upload_file_size': 259970
      },
      {
        'name': 'raw1_human_5k_cells_80_genes.cluster_3D.txt',
        'id': '60a2cf64cc7ba082358b5466',
        'file_type': 'Cluster',
        'upload_file_size': 297765,
        'bundled_files': [
          {
            'name': 'coordinate_labels.tsv',
            'id': '60a2cf65cc7ba082358b546a',
            'file_type': 'Coordinate Labels',
            'upload_file_size': 88
          }
        ]
      },
      {
        'name': 'raw1_human_5k_cells_80_genes.processed_dense.txt',
        'id': '60a2cf64cc7ba082358b5468',
        'file_type': 'Expression Matrix',
        'upload_file_size': 2274085
      },
      {
        'name': 'coordinate_labels.tsv',
        'id': '60a2cf65cc7ba082358b546a',
        'file_type': 'Coordinate Labels',
        'upload_file_size': 88
      }
    ]
  },
  {
    'name': 'Tuberculosis in female human lymph',
    'accession': 'SCP42',
    'study_source': 'SCP',
    'description': 'bleh',
    'study_files': [
      {
        'name': 'metadata.tsv',
        'id': '60a5ba1fcc7ba0360a9ac24f',
        'file_type': 'Metadata',
        'upload_file_size': 20027
      },
      {
        'name': 'expression_matrix.tsv',
        'id': '60a5ba1fcc7ba0360a9ac251',
        'file_type': 'Expression Matrix',
        'upload_file_size': 3465
      },
      {
        'name': 'cluster.tsv',
        'id': '60a5ba1fcc7ba0360a9ac253',
        'file_type': 'Cluster',
        'upload_file_size': 4473
      },
      {
        'name': 'cluster2.tsv',
        'id': '60a5ba20cc7ba0360a9ac255',
        'file_type': 'Cluster',
        'upload_file_size': 3206
      }
    ]
  }
]

describe('Download selection modal', () => {
  it('shows the correct total size, and generates a command with selected file ids', async () => {

    window.origin = 'http://localhost'

    const fetchDownloadInfo = jest.spyOn(ScpApi, 'fetchDownloadInfo')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchDownloadInfo.mockImplementation(() => Promise.resolve(
      camelcaseKeys(EXAMPLE_HUMAN_SYNTH_STUDY_DOWNLOAD_INFO)
    ))

    const fetchAuthCode = jest.spyOn(ScpApi, 'fetchAuthCode')
    // pass in a clone of the response since it may get modified by the cache operations
    fetchAuthCode.mockImplementation(() => Promise.resolve(
      { authCode: 'TViAHJmA', timeInterval: 1800, downloadId: 'aaaBBB' }
    ))

    render((
      <DownloadSelectionModal studyAccessions={['SCP12', 'SCP1', 'SCP35', 'SCP42']} show={true} setShow={() => {}}/>
    ))
    await waitForElementToBeRemoved(() => screen.getByTestId('bulk-download-loading-icon'))
    expect(screen.getByTestId('download-size-amount')).toHaveTextContent('3.1 MB')

    fireEvent.click(screen.getByText('1 files 215.1 KB'))
    expect(screen.getByTestId('download-size-amount')).toHaveTextContent('2.9 MB')

    fireEvent.click(screen.getByText('1 files 215.1 KB'))
    expect(screen.getByTestId('download-size-amount')).toHaveTextContent('3.1 MB')

    fireEvent.click(screen.getByText('Matrix'))
    expect(screen.getByTestId('download-size-amount')).toHaveTextContent('825.2 KB')

    fireEvent.click(screen.getByText('NEXT'))
    await waitForElementToBeRemoved(() => screen.getByTestId('bulk-download-loading-icon'))
    expect(screen.getByRole('textbox')).toHaveValue('curl "http://localhost/single_cell/api/v1/bulk_download/generate_curl_config?auth_code=TViAHJmA&context=global&download_id=aaaBBB" -o cfg.txt; curl -K cfg.txt && rm cfg.txt')
    expect(fetchAuthCode).toHaveBeenLastCalledWith([
      '60403d30cc7ba03f94477640',
      '60a2cf62cc7ba082358b545f',
      '60a2cf63cc7ba082358b5464',
      '60a2cf64cc7ba082358b5466',
      '60a5ba1fcc7ba0360a9ac24f',
      '60a5ba1fcc7ba0360a9ac253',
      '60a5ba20cc7ba0360a9ac255'
    ], {})
  })
})
