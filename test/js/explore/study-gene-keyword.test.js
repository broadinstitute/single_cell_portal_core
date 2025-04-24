import React from 'react'

import { render, waitFor, screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import StudyGeneField, {getIsInvalidQuery} from 'components/explore/StudyGeneField'
import { interestingNames, interactionCacheCsn1s1 } from './../visualization/pathway.test-data'

describe('Search query display text', () => {
  it('shows study result match for a valid search param', async () => {
    const { container } = render((
      <StudyGeneField queries={['PTEN']} queryFn={() => {}} allGenes={['PTEN']} speciesList={[]} />
    ))
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('PTEN')
  })

  it('shows study result matches for multiple valid search params', async () => {
    const { container } = render(
      <StudyGeneField queries={['PTEN', 'GENEA']} queryFn={() => {}} allGenes={['PTEN', 'GENEA', 'GENEB']} speciesList={[]} />
    )
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('PTENGENEA')
  })

  it('is disabled if there are no genes to search', async () => {
    const { container } = render(<StudyGeneField queries={[]} queryFn={() => {}} allGenes={['PTEN']} speciesList={[]} />)
    expect(container.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('Search gene(s) and find plots')

    const { container: emptyContainer } = render(<StudyGeneField queries={[]} queryFn={() => {}} allGenes={[]} speciesList={[]} />)
    expect(emptyContainer.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('No expression data to search')

    const { container: loadingContainer } = render(<StudyGeneField queries={[]} queryFn={() => {}} allGenes={[]} speciesList={[]} isLoading={true}/>)
    expect(loadingContainer.querySelector('.gene-keyword-search-input').textContent.trim()).toEqual('Search gene(s) and find plots')
  })

  it('responds to text input and shows matching gene options', async () => {
    const { container } = render(
      <StudyGeneField queries={[]} queryFn={() => {}} allGenes={['PTEN']} speciesList={[]} />
    )

    // Find the input field inside react-select
    const input = container.querySelector('[role="combobox"]')

    fireEvent.change(input, { target: { value: 'PT' } })

    expect(input).toHaveValue('PT')

    // Wait for dropdown to show
    await waitFor(() => {
      const ptenElement = screen.getByText(/PTEN/)
      expect(ptenElement).toBeInTheDocument()
    })
  })

  it('determines if query is valid for gene or pathway', async () => {
    // Mock Ideogram cache of gene names ranked by global interest
    window.Ideogram = {
      geneCache: { interestingNames },
      interactionCache: {"CSN1S1": interactionCacheCsn1s1},
      drawPathway: () => {
        document.dispatchEvent(new Event('ideogramDrawPathway'))
      }
    }

    const geneIsValid = getIsInvalidQuery('PT', ['PTEN'])
    expect(geneIsValid).toBe(true)

    const pathwayIsValid = getIsInvalidQuery('CSN1S1', ['PTEN'])
    expect(pathwayIsValid).toBe(true)
  })
})

