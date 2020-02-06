import React, { useState, useEffect } from 'react';
import Button from 'react-bootstrap/lib/Button';
import InputGroup from 'react-bootstrap/lib/InputGroup';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faExternalLinkAlt } from '@fortawesome/free-solid-svg-icons';
import isEqual from 'lodash/isEqual';

// import FiltersSearchBar from './FiltersSearchBar';


/**
 * Component for filter search and filter lists, and related functionality
 */
export default function FiltersBox(props) {
  const [canSave, setCanSave] = useState(false);
  const [savedSelection, setSavedSelection] = useState([]);
  const [selection, setSelection] = useState([]);

  useEffect(() => {
    setCanSave(!isEqual(selection, savedSelection));
  }, [selection]);

  useEffect(() => {
    setCanSave(false);
  }, [savedSelection]);

  // TODO: Get opinions, perhaps move to a UI code style guide.
  //
  // Systematic, predictable IDs help UX research and UI development.
  //
  // Form of IDs: <general name> <specific name(s)>
  // General name: All lowercase, specified in app code (e.g. 'save-facet', 'filter')
  // Specific name(s): Cased as specified in API (e.g. 'species', 'NCBItaxon9606')
  //
  // UI code concatenates names in the ID.  Names in ID are hyphen-delimited.
  //
  // Examples:
  //   * save-facet-species (for calls-to-action use ID: <action> <component>)
  //   * filter-species-NCBItaxon9606
  const facetName = props.facet.name;
  const componentName = 'filters-box';
  const filtersBoxID = `${componentName}-${facetName}`;
  const saveID = `save-${filtersBoxID}`;

  /**
   * Returns IDs of selected filters.
   * Enables comparing current vs. saved filters to enable/disable SAVE button
   */
  function getCheckedFilterIDs() {
    const checkedSelector = `#${filtersBoxID} input:checked`;
    const checkedFilterIDs =
      [...document.querySelectorAll(checkedSelector)].map((filter) => {
        return filter.id;
      });
    return checkedFilterIDs
  }

  function handleFilterClick() {
    setSelection(getCheckedFilterIDs());
  }

  function handleSaveClick(event) {
    const saveButtonClasses = Array.from(event.target.classList);
  
    if (saveButtonClasses.includes('disabled')) return;
    
    setSavedSelection(getCheckedFilterIDs());
  };

  return (
    <div className={componentName} id={filtersBoxID} style={{display: props.show ? '' : 'none'}}>
      {/* <FiltersSearchBar filtersBoxID={filtersBoxID} /> */}
      <p className='filters-box-header'>
        <span className='default-filters-list-name'>FREQUENTLY SEARCHED</span>
        <span className='facet-ontology-links'>
          {
          props.facet.links.map((link, i) => {
            return (
              <a key={`link-${i}`} href={link.url} target='_blank'>
                {link.name}&nbsp;&nbsp;<FontAwesomeIcon icon={faExternalLinkAlt}/><br/>
              </a>
            );
          })
          }
        </span>
      </p>
      <ul>
        {
          // TODO: Abstract to use Filters component 
          // after passing through function for onClick interaction
          // (SCP-2109)
          props.facet.filters.map((d) => {
            const id = `filter-${facetName}-${d.id}`;
            return (
              <li key={'li-' + id}>
                <InputGroup
                  id={id}
                  name={id}
                  onClick={handleFilterClick}
                >
                  <InputGroup.Addon>
                  <input type="checkbox" aria-label="Checkbox" />
                  </InputGroup.Addon>
                </InputGroup>
                <label htmlFor={id}>{d.name}</label>
              </li>
            );
          })
        }
      </ul>
      {/* 
      TODO: abstracting this and similar code block in
      FacetsAccordionBox into new component (SCP-2109)
       */}
      <div className='filters-box-footer'>
        <span>Clear</span>
        <Button 
          id={saveID}
          className={'facet-save-button ' + (canSave ? 'enabled' : 'disabled')}
          onClick={handleSaveClick}>
          SAVE
        </Button>
      </div>
    </div>
  );
}
