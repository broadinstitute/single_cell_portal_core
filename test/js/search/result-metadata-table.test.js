import React from 'react'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import ResultMetadataTable from '~/components/search/results/ResultMetadataTable'

const normalStudy = {
  accession: 'SCP1',
  metadata: {
    species: ['Homo sapiens'],
    disease: ['tuberculosis'],
    organ: ['lung', 'blood'],
    sex: ['male'],
    library_preparation_protocol: ['Drop-seq']
  }
}

const multiValueStudy = {
  accession: 'SCP2',
  metadata: {
    species: ['Homo sapiens'],
    disease: ['tuberculosis', 'HIV infections disease', 'hepatitis C virus infection'],
    organ: ['lung', 'blood', 'liver'],
    sex: [],
    library_preparation_protocol: []
  }
}

describe('Results metadata tables', () => {
  it('shows table with normal results', async () => {
    const { container } = render((
      <ResultMetadataTable study={normalStudy}/>
    ))
    expect(screen.getByTestId('SCP1-cohort-metadata')).toBeInTheDocument()
    expect(container.getElementsByClassName('study-metadata-entry')).toHaveLength(6)
  })

  it('shows table with expanded/unspecified results', async () => {
    const { container } = render((
      <ResultMetadataTable study={multiValueStudy}/>
    ))
    console.log(screen.debug())

    expect(screen.getByTestId('SCP2-cohort-metadata')).toBeInTheDocument()
    expect(container.getElementsByClassName('study-metadata-entry')).toHaveLength(9)
    expect(container.getElementsByClassName('more-metadata-entries')).toHaveLength(2)
    expect(container.getElementsByClassName('unspecified-entry')).toHaveLength(2)
  })
})
