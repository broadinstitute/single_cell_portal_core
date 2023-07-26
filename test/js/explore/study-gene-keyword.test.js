import React from 'react'

import { render } from '@testing-library/react'
import StudyGeneField from 'components/explore/StudyGeneField'


describe('Search query display text', () => {
  it('shows study result match for a valid search param', async () => {
    const { container } = render((
      <StudyGeneField genes={['PTEN']} searchGenes={() => {}} allGenes={['PTEN']} speciesList={[]} />
    ))
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('PTEN')
  })

  it('shows study result matches for multiple valid search params', async () => {
    const { container } = render(
      <StudyGeneField genes={['PTEN', 'GENEA']} searchGenes={() => {}} allGenes={['PTEN', 'GENEA', 'GENEB']} speciesList={[]} />
    )
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('PTENGENEA')
  })

  it('is disabled if there are no genes to search', async () => {
    const { container } = render(<StudyGeneField genes={[]} searchGenes={() => {}} allGenes={['PTEN']} speciesList={[]} />)
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('Search gene(s) and find plots')

    const { container: emptyContainer } = render(<StudyGeneField genes={[]} searchGenes={() => {}} allGenes={[]} speciesList={[]} />)
    expect(emptyContainer.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('No expression data to search')

    const { container: loadingContainer } = render(<StudyGeneField genes={[]} searchGenes={() => {}} allGenes={[]} speciesList={[]} isLoading={true}/>)
    expect(loadingContainer.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('Search gene(s) and find plots')
  })
})

