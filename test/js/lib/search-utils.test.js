import { getAutocompleteSuggestions, NUM_SUGGESTIONS } from 'lib/search-utils'

const targets = [
  'Tns1', 'Pik3ca', 'Pik3cd', 'Hvcn1', 'Tpte',
  'Tns3', 'Pter', 'Trp53', 'Slc9a3r2', 'Pten',
  'PTEN', 'FooPten',
  'Foo', 'Bar', 'Baz', 'Moo', 'Quux',
  'FOO', 'BAR', 'BAZ', 'MOO', 'QUUX',
  'FOO3', 'BAR3', 'BAZ3', 'MOO3', 'QUUX3',
  'g1', 'g2', 'g3', 'g4', 'g5',
  'g5', 'g6', 'g7', 'g8', 'g9',
  'g10', 'g11', 'g12', 'g13', 'g14',
  'g15', 'g16', 'g17', 'g18', 'g19',
  'g20', 'g21', 'g22', 'g23', 'g24'
]

describe('Search utilties', () => {
  it('suggests exact match first', async () => {
    const inputGene = 'PTEN'
    const suggestions = getAutocompleteSuggestions(inputGene, targets)

    expect(suggestions[0]).toEqual('PTEN')
    expect(suggestions).toHaveLength(NUM_SUGGESTIONS)
  })

  it('suggests close inexact match first', async () => {
    const inputGene = 'pdten'
    const suggestions = getAutocompleteSuggestions(inputGene, targets)

    expect(suggestions[0]).toEqual('Pten')
  })
})
