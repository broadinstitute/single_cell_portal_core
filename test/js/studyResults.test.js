import React from 'react'
import StudyResults from 'components/search/results/StudyResults'
import PagingControl from 'components/search/results/PagingControl'
import StudySearchResult from 'components/search/results/StudySearchResult'
import { render } from '@testing-library/react'

describe('<StudyResults/> rendering>', () => {
  const props = {
    changePage: jest.fn(),
    results: {
      currentPage: 1,
      totalPages: 4,
      studies: [{
        'accession': 'SCP1',
        'name': 'Study: Single nucleus RNA-seq of ',
        'cell_count': 0,
        'gene_count': 0,
        'study_url': '/single_cell/study/SCP1/study-single-nucleus',
        'metadata': {
          'species': ['Homo sapiens'],
          'disease': ['tuberculosis']
        }
      }]
    }
  }
  it('should render <StudyResults/> elements', () => {
    const { container } = render(<StudyResults changePage ={props.changePage} results={props.results} StudyComponent={StudySearchResult}/>)
    expect(container.getElementsByClassName('pagination')).toHaveLength(2)
    expect(container.getElementsByClassName('study-label')).toHaveLength(props.results.studies.length)
    expect(container.getElementsByClassName('cohort-metadata-table')).toHaveLength(props.results.studies.length)
  })

  it('should render the custom study component element', () => {
    const customComponent = () => {return <div className="test123">yo</div>}
    const { container } = render(<StudyResults changePage ={props.changePage} results={props.results} StudyComponent={customComponent}/>)
    expect(container.getElementsByClassName('pagination')).toHaveLength(2)
    expect(container.getElementsByClassName('test123')).toHaveLength(props.results.studies.length)
  })
})
