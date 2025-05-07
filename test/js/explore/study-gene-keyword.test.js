import React from 'react'

import { render, waitFor, screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import StudyGeneField, { getIsInvalidQuery, getIsEligibleForPathwayExplore } from 'components/explore/StudyGeneField'
import * as UserProvider from '~/providers/UserProvider'
import { interestingNames, interactionCacheCsn1s1 } from './../visualization/pathway.test-data'

describe('Search query display text', () => {
  beforeAll(() => {
    window.Ideogram = {
      geneCache: { interestingNames },
      interactionCache: { 'CSN1S1': interactionCacheCsn1s1 }
    }
  })

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

  it('responds to text input and shows matching pathway options', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    const { container } = render(
      <StudyGeneField
        queries={[]} queryFn={() => {}} allGenes={['PTEN']}
        speciesList={['Homo sapiens']} selectedAnnotation={{ type: 'group' }}
      />
    )

    // Find the input field inside react-select
    const input = container.querySelector('[role="combobox"]')

    fireEvent.change(input, { target: { value: 'CSN1S1' } })

    expect(input).toHaveValue('CSN1S1')

    // Wait for dropdown to show
    await waitFor(() => {
      const ptenElement = screen.getByText(/AMPK regulation of mammary milk protein synthesis/)
      expect(ptenElement).toBeInTheDocument()
    })
  })

  it('determines if query is valid for gene or pathway, with pathways on', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    const geneIsInvalid = getIsInvalidQuery('PT', ['PTEN'])
    expect(geneIsInvalid).toBe(true)

    const pathwayIsInvalid = getIsInvalidQuery('CSN1S1', ['PTEN'])
    expect(pathwayIsInvalid).toBe(false)
  })

  it('determines if view is eligible for pathway exploration', async () => {
    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_pathway_expression: true
      })

    // Confirm mouse is not eligible
    const isMouseEligible = getIsEligibleForPathwayExplore(['Mus musculus'], { type: 'group' })
    expect(isMouseEligible).toBe(false)

    // Confirm numeric annotation is not eligible
    const isNumericAnnotationEligible = getIsEligibleForPathwayExplore(['Homo sapiens'], { type: 'numeric' })
    expect(isNumericAnnotationEligible).toBe(false)

    // Confirm group annotation for human is eligible
    const isHumanGroupAnnotationEligible = getIsEligibleForPathwayExplore(['Homo sapiens'], { type: 'group' })
    expect(isHumanGroupAnnotationEligible).toBe(true)
  })

})

