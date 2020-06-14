import React, { useState } from 'react'
import Form from 'react-bootstrap/lib/Form'
import FormControl from 'react-bootstrap/lib/FormControl'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'

/**
 * Component to search filters within a given facet
 * Used when facet has many available filters (e.g. disease)
 */
export default function FiltersSearchBar({searchFilters, filtersBoxId}) {
  const [searchText, setSearchText] = useState('')

  async function handleFilterSearchSubmit(event) {
    event.preventDefault() // catch keyboard return and prevent form submit
    await searchFilters(searchText)
  }

  return (
    <div className='filters-search-bar'>
      <Form onSubmit={handleFilterSearchSubmit}>
        <FormControl
          id={`filters-search-bar-${filtersBoxId}`}
          type='text'
          autoComplete='false'
          placeholder='Search for a filter'
          value={searchText}
          onChange={e => setSearchText(e.target.value)}
        />
        <div className="input-group-append">
          <Button
            className='search-button'
            onClick={handleFilterSearchSubmit}
          >
            <FontAwesomeIcon icon={faSearch}/>
          </Button>
        </div>
      </Form>
    </div>
  )
}
