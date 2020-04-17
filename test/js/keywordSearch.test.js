import React from 'react'
import * as Reach from '@reach/router'
import { mount } from 'enzyme'

import KeywordSearch from 'components/search/controls/KeywordSearch'
import { PropsStudySearchProvider } from 'providers/StudySearchProvider';

describe('<KeywordSearch/> rendering>', () => {
  it('should render </KeywordSearch> elements', () => {
    const example = mount(<KeywordSearch/>)
    expect(example.exists('.study-keyword-search')).toEqual(true)
    expect(example.exists('.fa-search')).toEqual(true)
  })

  it('should show the clear button after text is entered', () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    const example = mount(
      <PropsStudySearchProvider searchParams={{terms: ''}}>
        <KeywordSearch/>
      </PropsStudySearchProvider>
    )
    expect(example.exists('button .fa-times')).toEqual(false)
    example.find('input[name="keywordText"]').first().simulate('change', {target: {value: 'test123'}});
     expect(example.exists('button .fa-times')).toEqual(true)
  })
})
