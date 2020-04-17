import React from 'react'
import StudyResults from 'components/search/results/StudyResults'
import PagingControl from 'components/search/results/PagingControl'
import Study from 'components/search/results/Study'
import { mount } from 'enzyme'

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
        'study_url': '/single_cell/study/SCP1/study-single-nucleus'
      }]
    }
  }
  it('should render <StudyResults/> elements', () => {
    const wrapper = mount(<StudyResults changePage ={props.changePage} results={props.results} StudyComponent={ Study }/>)
    expect(wrapper.find(PagingControl)).toHaveLength(2)
    expect(wrapper.find(Study)).toHaveLength(props.results.studies.length)
  })

  it('should render the custom study component element', () => {
    let customComponent = () => { return <div className="test123">yo</div> }
    const wrapper = mount(<StudyResults changePage ={props.changePage} results={props.results} StudyComponent={ customComponent }/>)
    expect(wrapper.find(PagingControl)).toHaveLength(2)
    expect(wrapper.find('.test123')).toHaveLength(props.results.studies.length)
  })
})
